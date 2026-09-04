import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';
import 'package:arcdash/models/bike_profile.dart';
import 'package:arcdash/models/map_favorite.dart';
import 'package:arcdash/models/range_prediction_state.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/providers/bike_selector_provider.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/map_provider.dart';
import 'package:arcdash/providers/stats_provider.dart';
import 'package:arcdash/providers/tuning_provider.dart';
import 'package:arcdash/services/navigation/map_favorites_repository.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:arcdash/services/sync/sync_api_client.dart';

class CloudSyncState {
  final SyncServerConfig config;
  final bool isSyncing;
  final DateTime? lastSyncTime;
  final String? statusMessage;
  final String? lastError;

  const CloudSyncState({
    required this.config,
    this.isSyncing = false,
    this.lastSyncTime,
    this.statusMessage,
    this.lastError,
  });

  bool get isAuthenticated => config.isAuthenticated;

  CloudSyncState copyWith({
    SyncServerConfig? config,
    bool? isSyncing,
    DateTime? lastSyncTime,
    String? statusMessage,
    String? lastError,
    bool clearError = false,
  }) {
    return CloudSyncState(
      config: config ?? this.config,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      statusMessage: statusMessage,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

class CloudSyncNotifier extends StateNotifier<CloudSyncState> {
  final Ref _ref;
  final SyncApiClient _client;

  CloudSyncNotifier(this._ref, {SyncApiClient? client})
      : _client = client ?? SyncApiClient(),
        super(const CloudSyncState(
          config: SyncServerConfig(serverUrl: defaultArcDashServerUrl),
        )) {
    _loadConfig();
  }

  void _loadConfig() {
    try {
      final storage = _ref.read(storageServiceProvider);
      // Hardcoded & transparent default server URL
      final savedUrl = storage.loadSyncServerUrl() ?? defaultArcDashServerUrl;
      final savedToken = storage.loadSyncToken();
      final savedUser = storage.loadSyncUsername();
      final savedUserId = storage.loadSyncUserId();
      final lastSync = storage.loadLastSyncTime();

      state = state.copyWith(
        config: SyncServerConfig(
          serverUrl: savedUrl,
          token: savedToken,
          userId: savedUserId,
          username: savedUser,
        ),
        lastSyncTime: lastSync,
      );

      // If logged in, kick off initial sync in background
      if (state.isAuthenticated) {
        syncNow();
      }
    } catch (_) {}
  }

  Future<bool> register({
    required String username,
    required String password,
    String? email,
    String? serverUrl,
  }) async {
    state = state.copyWith(isSyncing: true, clearError: true);
    final url = serverUrl ?? state.config.serverUrl;
    try {
      final res = await _client.register(
        serverUrl: url,
        username: username,
        password: password,
        email: email,
      );
      final token = res['access_token'] as String;
      final userId = res['user_id'] as String;

      final updatedConfig = state.config.copyWith(
        serverUrl: url,
        token: token,
        userId: userId,
        username: username,
      );

      final storage = _ref.read(storageServiceProvider);
      await storage.saveSyncConfig(
        serverUrl: url,
        token: token,
        userId: userId,
        username: username,
      );

      state = state.copyWith(
        config: updatedConfig,
        isSyncing: false,
        statusMessage: 'Registriert und angemeldet als $username!',
      );

      // Immediate first sync
      unawaited(syncNow());
      return true;
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        lastError: e
            .toString()
            .replaceAll('Exception: ', '')
            .replaceAll('HttpException: ', ''),
      );
      return false;
    }
  }

  Future<bool> login({
    required String username,
    required String password,
    String? serverUrl,
  }) async {
    state = state.copyWith(isSyncing: true, clearError: true);
    final url = serverUrl ?? state.config.serverUrl;
    try {
      final res = await _client.login(
        serverUrl: url,
        username: username,
        password: password,
      );
      final token = res['access_token'] as String;
      final userId = res['user_id'] as String;

      final updatedConfig = state.config.copyWith(
        serverUrl: url,
        token: token,
        userId: userId,
        username: username,
      );

      final storage = _ref.read(storageServiceProvider);
      await storage.saveSyncConfig(
        serverUrl: url,
        token: token,
        userId: userId,
        username: username,
      );

      state = state.copyWith(
        config: updatedConfig,
        isSyncing: false,
        statusMessage: 'Erfolgreich eingeloggt als $username!',
      );

      // Immediate first sync
      unawaited(syncNow());
      return true;
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        lastError: e
            .toString()
            .replaceAll('Exception: ', '')
            .replaceAll('HttpException: ', ''),
      );
      return false;
    }
  }

  Future<void> logout() async {
    final storage = _ref.read(storageServiceProvider);
    await storage.clearSyncConfig();
    state = state.copyWith(
      config: state.config.copyWith(clearAuth: true),
      statusMessage: 'Abgemeldet.',
      clearError: true,
    );
  }

  /// Bidirectional sync: Push local data, then Pull updates from server.
  Future<bool> syncNow() async {
    if (!state.isAuthenticated || state.isSyncing) return false;

    state = state.copyWith(
        isSyncing: true, clearError: true, statusMessage: 'Synchronisiere...');

    final storage = _ref.read(storageServiceProvider);
    final token = state.config.token!;
    final serverUrl = state.config.serverUrl;

    try {
      // 1. Prepare local Bikes & Tuning Profiles for Push
      final localBikes = storage.loadBikes();
      final localProfiles = storage.loadProfiles();
      final localRides = storage.loadRideSessions();

      // Map Favorites & Recents
      final favRepo = _ref.read(mapFavoritesRepositoryProvider);
      final localFavs = favRepo.loadFavorites();
      final localRecents = favRepo.loadRecents();

      // Range Calibration State
      final rangeRepo = _ref.read(rangePredictionRepositoryProvider);
      final currentCtrlId = _ref.read(connectedDeviceIdProvider) ??
          storage.loadLastControllerId() ??
          '';
      final rangeState = rangeRepo.loadState(controllerId: currentCtrlId);

      final pushPayload = {
        'bikes': localBikes
            .map((b) => {
                  'id': b.id,
                  'name': b.name,
                  'controller_id': b.controllerId,
                  'controller_name': b.controllerName,
                  'bms_id': b.bmsId,
                  'bms_name': b.bmsName,
                  'is_auto_connect': storage.loadAutoConnectBikeId() == b.id,
                  'created_at': b.createdAt.toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                  'deleted_at': null,
                })
            .toList(),
        'tuning_profiles': localProfiles
            .map((p) => {
                  'id': p.name,
                  'name': p.name,
                  'is_stock': p.isStock,
                  'max_speed_kph': p.maxSpeedKph,
                  'max_line_curr_a': p.maxLineCurrA,
                  'max_phase_curr_a': p.maxPhaseCurrA,
                  'throttle_response': p.throttleResponse,
                  'boost_seconds': p.boostTimeSeconds,
                  'power_curve_json': '[]',
                  'regen_curve_json': '[]',
                  'pin_mapping_json': '{}',
                  'is_public': false,
                  'version': 1,
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                  'deleted_at': null,
                })
            .toList(),
        'rides': localRides
            .map((r) => {
                  'id': r['id']?.toString() ??
                      DateTime.now().millisecondsSinceEpoch.toString(),
                  'bike_id': storage.loadSelectedBikeId(),
                  'start_time':
                      r['startTime'] ?? DateTime.now().toIso8601String(),
                  'end_time': r['endTime'] ?? DateTime.now().toIso8601String(),
                  'duration_sec': (r['durationSec'] as num?)?.toInt() ?? 0,
                  'distance_km': (r['distanceKm'] as num?)?.toDouble() ?? 0.0,
                  'avg_speed_kph':
                      (r['avgSpeedKph'] as num?)?.toDouble() ?? 0.0,
                  'max_speed_kph':
                      (r['maxSpeedKph'] as num?)?.toDouble() ?? 0.0,
                  'energy_used_wh':
                      (r['totalWhUsed'] as num?)?.toDouble() ?? 0.0,
                  'efficiency_wh_per_km':
                      (r['efficiencyWhPerKm'] as num?)?.toDouble() ?? 0.0,
                  'max_motor_temp_c': 0.0,
                  'max_controller_temp_c': 0.0,
                  'telemetry_blob': jsonEncode(r),
                  'created_at':
                      r['startTime'] ?? DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                  'deleted_at': null,
                })
            .toList(),
        'map_favorites': [
          ...localFavs.map((f) => {
                'id': f.id,
                'title': f.title,
                'subtitle': f.subtitle,
                'lat': f.location.latitude,
                'lon': f.location.longitude,
                'type': f.type.name,
                'created_at': f.createdAt.toIso8601String(),
                'updated_at': DateTime.now().toIso8601String(),
                'deleted_at': null,
              }),
          ...localRecents.map((f) => {
                'id': f.id,
                'title': f.title,
                'subtitle': f.subtitle,
                'lat': f.location.latitude,
                'lon': f.location.longitude,
                'type': 'recent',
                'created_at': f.createdAt.toIso8601String(),
                'updated_at': DateTime.now().toIso8601String(),
                'deleted_at': null,
              }),
        ],
        'range_calibrations': rangeState != null
            ? [
                {
                  'controller_id': rangeState.controllerId.isNotEmpty
                      ? rangeState.controllerId
                      : (currentCtrlId.isNotEmpty ? currentCtrlId : 'default'),
                  'learned_capacity_wh': rangeState.learnedCapacityWh,
                  'soc_confidence': rangeState.socConfidence,
                  'consumption_history_json':
                      jsonEncode(rangeState.consumptionHistoryWhPerKm),
                  'min_voltage_v': rangeState.minVoltageV,
                  'max_voltage_v': rangeState.maxVoltageV,
                  'updated_at': DateTime.now().toIso8601String(),
                }
              ]
            : [],
      };

      // Push to server
      await _client.pushSync(
        serverUrl: serverUrl,
        token: token,
        payload: pushPayload,
      );

      // 2. Pull latest data from server
      final pullData = await _client.pullSync(
        serverUrl: serverUrl,
        token: token,
        since: state.lastSyncTime,
      );

      final serverTime = DateTime.parse(pullData['server_time'] as String);

      // Ingest remote bikes
      final remoteBikes = (pullData['bikes'] as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();
      for (final rb in remoteBikes) {
        final id = rb['id'] as String;
        final deletedAt = rb['deleted_at'];
        if (deletedAt != null) {
          await storage.deleteBike(id);
        } else {
          final bike = BikeProfile(
            id: id,
            name: rb['name'] as String,
            controllerId: rb['controller_id'] as String? ?? '',
            controllerName:
                rb['controller_name'] as String? ?? 'FarDriver Controller',
            bmsId: rb['bms_id'] as String? ?? '',
            bmsName: rb['bms_name'] as String? ?? 'ANT BMS',
            createdAt: DateTime.parse(rb['created_at'] as String),
          );
          await storage.saveBike(bike);
          if (rb['is_auto_connect'] == true) {
            await storage.saveAutoConnectBikeId(bike.id);
          }
        }
      }

      // Ingest remote tuning profiles
      final remoteProfiles = (pullData['tuning_profiles'] as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();
      for (final rp in remoteProfiles) {
        final name = rp['name'] as String;
        final deletedAt = rp['deleted_at'];
        if (deletedAt != null) {
          await storage.deleteProfile(name);
        } else {
          final prof = TuningProfile.custom().copyWith(
            name: name,
            isStock: rp['is_stock'] as bool? ?? false,
            maxSpeedKph: (rp['max_speed_kph'] as num).toDouble(),
            maxLineCurrA: (rp['max_line_curr_a'] as num).toDouble(),
            maxPhaseCurrA: (rp['max_phase_curr_a'] as num).toDouble(),
            throttleResponse: (rp['throttle_response'] as num).toInt(),
            boostTimeSeconds: (rp['boost_seconds'] as num).toInt(),
          );
          await storage.saveProfile(prof);
        }
      }

      // Ingest remote rides
      final remoteRides = (pullData['rides'] as List? ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      for (final rr in remoteRides) {
        final id = rr['id'] as String;
        final deletedAt = rr['deleted_at'];
        if (deletedAt == null) {
          final existingSessions = storage.loadRideSessions();
          final exists = existingSessions.any((s) => s['id']?.toString() == id);
          if (!exists) {
            Map<String, dynamic>? sessionData;
            if (rr['telemetry_blob'] != null &&
                rr['telemetry_blob'].isNotEmpty) {
              try {
                sessionData =
                    jsonDecode(rr['telemetry_blob']) as Map<String, dynamic>;
              } catch (_) {}
            }
            sessionData ??= {
              'id': id,
              'startTime': rr['start_time'],
              'endTime': rr['end_time'],
              'durationSec': rr['duration_sec'],
              'distanceKm': rr['distance_km'],
              'avgSpeedKph': rr['avg_speed_kph'],
              'maxSpeedKph': rr['max_speed_kph'],
              'totalWhUsed': rr['energy_used_wh'],
              'efficiencyWhPerKm': rr['efficiency_wh_per_km'],
              'speedHistory': [],
            };
            // Append and save
            existingSessions.add(sessionData);
            // Save through storage service
            await storage.saveRawSessionList(existingSessions);
          }
        }
      }

      // Ingest remote map favorites & recents
      final remoteFavorites = (pullData['map_favorites'] as List? ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      for (final rf in remoteFavorites) {
        final id = rf['id'] as String;
        final deletedAt = rf['deleted_at'];
        final favTypeStr = (rf['type'] as String? ?? 'custom').toLowerCase();

        if (favTypeStr == 'recent') {
          if (deletedAt == null) {
            final recent = MapFavorite(
              id: id,
              title: rf['title'] as String,
              subtitle: rf['subtitle'] as String? ?? '',
              location: GeoLatLng(
                latitude: (rf['lat'] as num).toDouble(),
                longitude: (rf['lon'] as num).toDouble(),
              ),
              type: FavoriteType.recent,
              createdAt: DateTime.parse(rf['created_at'] as String),
            );
            favRepo.addRecent(recent);
          }
        } else {
          final curFavs = favRepo.loadFavorites();
          if (deletedAt != null) {
            curFavs.removeWhere((f) => f.id == id);
            favRepo.saveFavorites(curFavs);
          } else {
            final fType = switch (favTypeStr) {
              'home' => FavoriteType.home,
              'work' => FavoriteType.work,
              _ => FavoriteType.custom,
            };
            final fav = MapFavorite(
              id: id,
              title: rf['title'] as String,
              subtitle: rf['subtitle'] as String? ?? '',
              location: GeoLatLng(
                latitude: (rf['lat'] as num).toDouble(),
                longitude: (rf['lon'] as num).toDouble(),
              ),
              type: fType,
              createdAt: DateTime.parse(rf['created_at'] as String),
            );
            curFavs.removeWhere((f) => f.id == id);
            curFavs.add(fav);
            favRepo.saveFavorites(curFavs);
          }
        }
      }

      // Ingest remote range calibrations
      final remoteCalibrations = (pullData['range_calibrations'] as List? ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      for (final rc in remoteCalibrations) {
        final ctrlId = rc['controller_id'] as String;
        List<double> history = [];
        try {
          final rawHist = jsonDecode(rc['consumption_history_json'] ?? '[]');
          if (rawHist is List) {
            history = rawHist.map((v) => (v as num).toDouble()).toList();
          }
        } catch (_) {}

        final calState = RangePredictionState(
          controllerId: ctrlId,
          learnedCapacityWh: (rc['learned_capacity_wh'] as num).toDouble(),
          socConfidence: (rc['soc_confidence'] as num).toDouble(),
          consumptionHistoryWhPerKm: history,
          minVoltageV: (rc['min_voltage_v'] as num).toDouble(),
          maxVoltageV: (rc['max_voltage_v'] as num).toDouble(),
        );
        rangeRepo.saveState(calState);
      }

      // Update Last Sync Time
      await storage.saveLastSyncTime(serverTime);

      // Refresh providers so UI updates immediately across all screens!
      _ref.read(bikeSelectorProvider.notifier).refreshFromStorage();
      _ref.read(tuningProvider.notifier).refreshFromStorage();
      _ref.read(statsProvider.notifier).refreshFromStorage();
      _ref.read(mapControllerProvider.notifier).refreshFromStorage();
      _ref.read(rangePredictionStateProvider.notifier)?.refreshFromStorage();

      state = state.copyWith(
        isSyncing: false,
        lastSyncTime: serverTime,
        statusMessage:
            'Synchronisierung erfolgreich (${serverTime.hour.toString().padLeft(2, "0")}:${serverTime.minute.toString().padLeft(2, "0")} Uhr)!',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        lastError: 'Sync-Fehler: $e',
      );
      return false;
    }
  }
}

final cloudSyncProvider =
    StateNotifierProvider<CloudSyncNotifier, CloudSyncState>((ref) {
  return CloudSyncNotifier(ref);
});
