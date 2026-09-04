import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:arcdash/models/bike_profile.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/models/ride_stats.dart';
import 'package:arcdash/models/dashboard_layout.dart';
import 'package:arcdash/services/dashboard_layout_repository.dart';
import 'package:arcdash/services/versioned_json_repository.dart';
import 'package:arcdash/services/range_prediction_repository.dart';
import 'package:csv/csv.dart';

const _prefKeyStockBackup = 'stock_backup_json';
const _prefKeyProfiles = 'tuning_profiles';
const _prefKeyRideSessions = 'ride_sessions';
const _prefKeyFirstConnect = 'first_connect_done';
const _prefKeyLastControllerId = 'last_controller_id';
const _prefKeyLastBmsId = 'last_bms_id';
const _prefKeyBikes = 'saved_bikes';
const _prefKeySelectedBikeId = 'selected_bike_id';
const _prefKeyAutoConnectBikeId = 'auto_connect_bike_id';
const _prefKeySyncServerUrl = 'sync_server_url';
const _prefKeySyncToken = 'sync_token';
const _prefKeySyncUserId = 'sync_user_id';
const _prefKeySyncUsername = 'sync_username';
const _prefKeyLastSyncTime = 'last_sync_time';

class StorageService {
  late SharedPreferences _prefs;
  bool _initialized = false;
  DashboardLayout _dashboardLayout = DashboardLayout.defaults();
  DashboardLayoutRepository? _dashboardRepository;
  DashboardLayoutLoadStatus dashboardLayoutStatus =
      DashboardLayoutLoadStatus.missing;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final directory = await getApplicationSupportDirectory();
    _dashboardRepository = DashboardLayoutRepository(VersionedJsonRepository(
      store:
          AtomicJsonFileStore(File('${directory.path}/dashboard-layout.json')),
      type: DashboardLayoutRepository.documentType,
      schemaVersion: DashboardLayoutRepository.documentVersion,
    ));
    final loaded = await _dashboardRepository!.load();
    _dashboardLayout = loaded.layout;
    dashboardLayoutStatus = loaded.status;
    if (loaded.status == DashboardLayoutLoadStatus.missing) {
      await _migrateLegacyDashboardLayout();
    }
    _initialized = true;
  }

  bool get isInitialized => _initialized;

  /// Key-value storage for the range prediction / voltage calibration state.
  /// Gracefully degrades to a no-op store when not initialized (e.g. in tests).
  KeyValueStorage get rangePredictionStorage =>
      SharedPreferencesKeyValueStorage(_initialized ? _prefs : null);

  DashboardLayout loadDashboardLayout() {
    return _dashboardLayout;
  }

  Future<void> saveDashboardLayout(DashboardLayout layout) async {
    layout.portrait.validate();
    layout.landscape.validate();
    _dashboardLayout = layout;
    if (!_initialized) return;
    await _dashboardRepository!.save(layout);
    dashboardLayoutStatus = DashboardLayoutLoadStatus.loaded;
  }

  Future<void> resetDashboardLayout() async {
    _dashboardLayout = DashboardLayout.defaults();
    if (_initialized) {
      await _dashboardRepository!.save(_dashboardLayout);
      await _prefs.remove('dashboard_layout');
      dashboardLayoutStatus = DashboardLayoutLoadStatus.loaded;
    }
  }

  Future<void> _migrateLegacyDashboardLayout() async {
    final encoded = _prefs.getString('dashboard_layout');
    if (encoded == null) return;
    try {
      final legacy = DashboardLayout.fromJson(jsonDecode(encoded));
      await _dashboardRepository!.save(legacy);
      _dashboardLayout = legacy;
      dashboardLayoutStatus = DashboardLayoutLoadStatus.loaded;
      await _prefs.remove('dashboard_layout');
    } on Object {
      dashboardLayoutStatus = DashboardLayoutLoadStatus.corrupt;
    }
  }

  Future<void> clearRideSessions() async {
    if (_initialized) await _prefs.remove(_prefKeyRideSessions);
  }

  Future<void> clearProfiles() async {
    if (_initialized) await _prefs.remove(_prefKeyProfiles);
  }

  // --- Stock backup ---
  bool get hasStockBackup =>
      _initialized && _prefs.containsKey(_prefKeyStockBackup);

  Future<void> saveStockBackup(Map<int, int> rawAddressValues) async {
    if (!_initialized) return;
    final encoded = jsonEncode(rawAddressValues.map(
      (k, v) => MapEntry(k.toString(), v),
    ));
    await _prefs.setString(_prefKeyStockBackup, encoded);
    await _prefs.setBool(_prefKeyFirstConnect, true);
  }

  Map<int, int>? loadStockBackup() {
    if (!_initialized) return null;
    final s = _prefs.getString(_prefKeyStockBackup);
    if (s == null) return null;
    final map = jsonDecode(s) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(int.parse(k), v as int));
  }

  bool get firstConnectDone =>
      _initialized && (_prefs.getBool(_prefKeyFirstConnect) ?? false);

  // --- Dual-BLE auto-remember ---
  Future<void> saveLastControllerId(String remoteId) async {
    if (!_initialized || remoteId.isEmpty) return;
    await _prefs.setString(_prefKeyLastControllerId, remoteId);
  }

  String? loadLastControllerId() =>
      _initialized ? _prefs.getString(_prefKeyLastControllerId) : null;

  Future<void> saveLastBmsId(String remoteId) async {
    if (!_initialized || remoteId.isEmpty) return;
    await _prefs.setString(_prefKeyLastBmsId, remoteId);
  }

  String? loadLastBmsId() =>
      _initialized ? _prefs.getString(_prefKeyLastBmsId) : null;

  // --- Bike Profiles Management ---
  Future<void> saveBike(BikeProfile bike) async {
    if (!_initialized) return;
    final bikes = loadBikes();
    final idx = bikes.indexWhere((b) => b.id == bike.id);
    if (idx >= 0) {
      bikes[idx] = bike;
    } else {
      bikes.add(bike);
    }
    await _prefs.setString(
      _prefKeyBikes,
      jsonEncode(bikes.map((b) => b.toJson()).toList()),
    );
  }

  List<BikeProfile> loadBikes() {
    if (!_initialized) return [];
    final s = _prefs.getString(_prefKeyBikes);
    if (s == null) return [];
    try {
      final list = jsonDecode(s) as List;
      return list
          .map((e) => BikeProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteBike(String id) async {
    if (!_initialized) return;
    final bikes = loadBikes()..removeWhere((b) => b.id == id);
    await _prefs.setString(
      _prefKeyBikes,
      jsonEncode(bikes.map((b) => b.toJson()).toList()),
    );
    if (loadAutoConnectBikeId() == id) {
      await saveAutoConnectBikeId(null);
    }
    if (loadSelectedBikeId() == id) {
      await saveSelectedBikeId(bikes.isNotEmpty ? bikes.first.id : null);
    }
  }

  Future<void> saveSelectedBikeId(String? bikeId) async {
    if (!_initialized) return;
    if (bikeId == null || bikeId.isEmpty) {
      await _prefs.remove(_prefKeySelectedBikeId);
    } else {
      await _prefs.setString(_prefKeySelectedBikeId, bikeId);
    }
  }

  String? loadSelectedBikeId() =>
      _initialized ? _prefs.getString(_prefKeySelectedBikeId) : null;

  Future<void> saveAutoConnectBikeId(String? bikeId) async {
    if (!_initialized) return;
    if (bikeId == null || bikeId.isEmpty) {
      await _prefs.remove(_prefKeyAutoConnectBikeId);
    } else {
      await _prefs.setString(_prefKeyAutoConnectBikeId, bikeId);
    }
  }

  String? loadAutoConnectBikeId() =>
      _initialized ? _prefs.getString(_prefKeyAutoConnectBikeId) : null;

  // --- Cloud Sync Config Persistence ---
  Future<void> saveSyncConfig({
    required String serverUrl,
    required String token,
    required String userId,
    required String username,
  }) async {
    if (!_initialized) return;
    await _prefs.setString(_prefKeySyncServerUrl, serverUrl);
    await _prefs.setString(_prefKeySyncToken, token);
    await _prefs.setString(_prefKeySyncUserId, userId);
    await _prefs.setString(_prefKeySyncUsername, username);
  }

  Future<void> clearSyncConfig() async {
    if (!_initialized) return;
    await _prefs.remove(_prefKeySyncToken);
    await _prefs.remove(_prefKeySyncUserId);
    await _prefs.remove(_prefKeySyncUsername);
    await _prefs.remove(_prefKeyLastSyncTime);
  }

  String? loadSyncServerUrl() =>
      _initialized ? _prefs.getString(_prefKeySyncServerUrl) : null;

  String? loadSyncToken() =>
      _initialized ? _prefs.getString(_prefKeySyncToken) : null;

  String? loadSyncUserId() =>
      _initialized ? _prefs.getString(_prefKeySyncUserId) : null;

  String? loadSyncUsername() =>
      _initialized ? _prefs.getString(_prefKeySyncUsername) : null;

  Future<void> saveLastSyncTime(DateTime time) async {
    if (!_initialized) return;
    await _prefs.setString(_prefKeyLastSyncTime, time.toIso8601String());
  }

  DateTime? loadLastSyncTime() {
    if (!_initialized) return null;
    final s = _prefs.getString(_prefKeyLastSyncTime);
    return s != null ? DateTime.tryParse(s) : null;
  }

  // --- Tuning profiles ---
  Future<void> saveProfile(TuningProfile profile) async {
    if (!_initialized) return;
    final profiles = loadProfiles();
    final idx = profiles.indexWhere((p) => p.name == profile.name);
    if (idx >= 0) {
      profiles[idx] = profile;
    } else {
      profiles.add(profile);
    }
    await _prefs.setString(
      _prefKeyProfiles,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
  }

  List<TuningProfile> loadProfiles() {
    if (!_initialized) return [];
    final s = _prefs.getString(_prefKeyProfiles);
    if (s == null) return [];
    try {
      final list = jsonDecode(s) as List;
      return list
          .map((e) => TuningProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteProfile(String name) async {
    if (!_initialized) return;
    final profiles = loadProfiles()..removeWhere((p) => p.name == name);
    await _prefs.setString(
      _prefKeyProfiles,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
  }

  // --- Fast Map Configuration ---
  static const _prefKeyFastMapTunedProfile = 'fast_map_tuned_profile';
  static const _prefKeyFastMapStockProfile = 'fast_map_stock_profile';
  static const _prefKeyFastMapAutoApply = 'fast_map_auto_apply';

  Future<void> saveFastMapConfig({
    String? tunedProfile,
    String? stockProfile,
    bool? autoApplyOnConnect,
  }) async {
    if (!_initialized) return;
    if (tunedProfile != null) {
      await _prefs.setString(_prefKeyFastMapTunedProfile, tunedProfile);
    }
    if (stockProfile != null) {
      await _prefs.setString(_prefKeyFastMapStockProfile, stockProfile);
    }
    if (autoApplyOnConnect != null) {
      await _prefs.setBool(_prefKeyFastMapAutoApply, autoApplyOnConnect);
    }
  }

  String? loadFastMapTunedProfile() =>
      _initialized ? _prefs.getString(_prefKeyFastMapTunedProfile) : null;

  String loadFastMapStockProfile() => _initialized
      ? (_prefs.getString(_prefKeyFastMapStockProfile) ?? 'Stock Street Legal')
      : 'Stock Street Legal';

  bool loadFastMapAutoApply() => _initialized
      ? (_prefs.getBool(_prefKeyFastMapAutoApply) ?? false)
      : false;

  // --- Ride sessions ---
  Future<void> saveRawSessionList(List<Map<String, dynamic>> sessions) async {
    if (!_initialized) return;
    final trimmed = sessions.length > 50
        ? sessions.sublist(sessions.length - 50)
        : sessions;
    await _prefs.setString(_prefKeyRideSessions, jsonEncode(trimmed));
  }

  Future<void> saveRideSession(RideSession session) async {
    if (!_initialized) return;
    final sessions = _loadSessionJsonList();
    sessions.add(session.toJson());
    // Keep only last 50 sessions
    final trimmed = sessions.length > 50
        ? sessions.sublist(sessions.length - 50)
        : sessions;
    await _prefs.setString(_prefKeyRideSessions, jsonEncode(trimmed));
  }

  List<Map<String, dynamic>> _loadSessionJsonList() {
    if (!_initialized) return [];
    final s = _prefs.getString(_prefKeyRideSessions);
    if (s == null) return [];
    try {
      return (jsonDecode(s) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  List<Map<String, dynamic>> loadRideSessions() => _loadSessionJsonList();

  // --- CSV export ---
  Future<String> exportSessionToCsv(RideSession session) async {
    final rows = session.toCsvRows();
    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        '${dir.path}/arcdash_ride_${session.startTime.millisecondsSinceEpoch}.csv');
    await file.writeAsString(csv);
    return file.path;
  }

  Future<void> clearAll() async {
    if (_initialized) await _prefs.clear();
  }
}
