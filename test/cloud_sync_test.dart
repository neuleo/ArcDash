import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:arcdash/models/bike_profile.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/providers/cloud_sync_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:arcdash/services/sync/sync_api_client.dart';

import 'tuning_v2_test.dart' as t2;

class _SyncMemoryStorage extends StorageService {
  final List<BikeProfile> _bikes = [];
  final List<TuningProfile> _profiles = [];
  String? _token;
  String? _userId;
  String? _username;
  String? _serverUrl;
  DateTime? _lastSync;

  @override
  bool get isInitialized => true;

  @override
  List<BikeProfile> loadBikes() => List.unmodifiable(_bikes);

  @override
  Future<void> saveBike(BikeProfile bike) async {
    _bikes.removeWhere((b) => b.id == bike.id);
    _bikes.add(bike);
  }

  @override
  Future<void> deleteBike(String id) async =>
      _bikes.removeWhere((b) => b.id == id);

  @override
  List<TuningProfile> loadProfiles() => List.unmodifiable(_profiles);

  @override
  Future<void> saveProfile(TuningProfile profile) async {
    _profiles.removeWhere((p) => p.name == profile.name);
    _profiles.add(profile);
  }

  @override
  Future<void> deleteProfile(String name) async =>
      _profiles.removeWhere((p) => p.name == name);

  @override
  Future<void> saveSyncConfig({
    required String serverUrl,
    required String token,
    required String userId,
    required String username,
  }) async {
    _serverUrl = serverUrl;
    _token = token;
    _userId = userId;
    _username = username;
  }

  @override
  Future<void> clearSyncConfig() async {
    _token = null;
    _userId = null;
    _username = null;
    _lastSync = null;
  }

  @override
  String? loadSyncServerUrl() => _serverUrl;
  @override
  String? loadSyncToken() => _token;
  @override
  String? loadSyncUserId() => _userId;
  @override
  String? loadSyncUsername() => _username;
  @override
  DateTime? loadLastSyncTime() => _lastSync;
  @override
  Future<void> saveLastSyncTime(DateTime time) async => _lastSync = time;
}

void main() {
  group('CloudSyncProvider & SyncApiClient Tests', () {
    test('Register and Login with Mock HTTP client', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/register')) {
          return http.Response(
            jsonEncode({
              'access_token': 'jwt_mock_token_123',
              'user_id': 'uid_456',
              'username': 'leon',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path.endsWith('/push')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'server_time': DateTime.now().toIso8601String(),
              'bikes_processed': 1,
              'tuning_profiles_processed': 1,
              'rides_processed': 0,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path.endsWith('/pull')) {
          return http.Response(
            jsonEncode({
              'server_time': DateTime.now().toIso8601String(),
              'bikes': [
                {
                  'id': 'remote_bike_1',
                  'name': 'Cloud Leopard',
                  'controller_id': 'FD:CL:01',
                  'controller_name': 'FarDriver',
                  'bms_id': 'ANT:CL:02',
                  'bms_name': 'ANT BMS',
                  'is_auto_connect': true,
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                  'deleted_at': null,
                }
              ],
              'tuning_profiles': [
                {
                  'id': 'Remote Trail',
                  'name': 'Remote Trail',
                  'is_stock': false,
                  'max_speed_kph': 70.0,
                  'max_line_curr_a': 110.0,
                  'max_phase_curr_a': 250.0,
                  'throttle_response': 2,
                  'boost_seconds': 12,
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                  'deleted_at': null,
                }
              ],
              'rides': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final storage = _SyncMemoryStorage();
      final syncApiClient = SyncApiClient(client: mockClient);

      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          cloudSyncProvider.overrideWith(
              (ref) => CloudSyncNotifier(ref, client: syncApiClient)),
        ],
      );
      addTearDown(container.dispose);

      final syncNotifier = container.read(cloudSyncProvider.notifier);

      final registered = await syncNotifier.register(
        username: 'leon',
        password: 'password123',
        serverUrl: 'http://localhost:8080',
      );

      expect(registered, isTrue);
      expect(container.read(cloudSyncProvider).isAuthenticated, isTrue);
      expect(container.read(cloudSyncProvider).config.username, 'leon');

      // Sync should have pulled remote bike and tuning profile
      await Future.delayed(const Duration(milliseconds: 100));
      await syncNotifier.syncNow();
      expect(storage.loadBikes(), hasLength(1));
      expect(storage.loadBikes().first.name, 'Cloud Leopard');
      expect(storage.loadProfiles(), hasLength(1));
      expect(storage.loadProfiles().first.name, 'Remote Trail');

      await syncNotifier.logout();
      expect(container.read(cloudSyncProvider).isAuthenticated, isFalse);
    });
  });
}
