import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/bike_profile.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/providers/bike_selector_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/tuning_provider.dart';
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
                  'id': p.name, // Profile name serves as key
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
        'rides': [],
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

      // Update Last Sync Time
      await storage.saveLastSyncTime(serverTime);

      // Refresh providers so UI updates immediately
      _ref.read(bikeSelectorProvider.notifier);
      _ref.read(tuningProvider.notifier);

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
