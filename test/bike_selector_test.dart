import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/bike_profile.dart';
import 'package:arcdash/providers/bike_selector_provider.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/ant_bms_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/services/ant_bms_service.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/dual_ble_auto_connect.dart';
import 'package:arcdash/services/storage_service.dart';

import 'tuning_v2_test.dart' as t2;

class _BikeMemoryStorage extends StorageService {
  final List<BikeProfile> _bikes = [];
  String? _selectedId;
  String? _autoConnectId;

  @override
  bool get isInitialized => true;

  @override
  Future<void> saveBike(BikeProfile bike) async {
    final idx = _bikes.indexWhere((b) => b.id == bike.id);
    if (idx >= 0) {
      _bikes[idx] = bike;
    } else {
      _bikes.add(bike);
    }
  }

  @override
  List<BikeProfile> loadBikes() => List.unmodifiable(_bikes);

  @override
  Future<void> deleteBike(String id) async {
    _bikes.removeWhere((b) => b.id == id);
    if (_autoConnectId == id) _autoConnectId = null;
    if (_selectedId == id)
      _selectedId = _bikes.isNotEmpty ? _bikes.first.id : null;
  }

  @override
  Future<void> saveSelectedBikeId(String? id) async => _selectedId = id;

  @override
  String? loadSelectedBikeId() => _selectedId;

  @override
  Future<void> saveAutoConnectBikeId(String? id) async => _autoConnectId = id;

  @override
  String? loadAutoConnectBikeId() => _autoConnectId;
}

class _MockBmsService extends AntBmsService {
  final List<String> connectByIdCalls = [];

  @override
  DongleConnectionState get state => DongleConnectionState.idle;

  @override
  Stream<DongleConnectionState> get connectionStateStream =>
      const Stream.empty();

  @override
  Stream<List<int>> get rawDataStream => const Stream.empty();

  @override
  Stream<List<DiscoveredDongle>> get scanResultsStream => const Stream.empty();

  @override
  Future<bool> connectById(String remoteId, {String? name}) async {
    connectByIdCalls.add(remoteId);
    return true;
  }
}

void main() {
  group('BikeProfile & BikeSelector Tests', () {
    test('BikeProfile JSON serialization and copyWith', () {
      final now = DateTime.now();
      final bike = BikeProfile(
        id: 'bike_1',
        name: 'Arctic Leopard L1E',
        controllerId: 'FD:01:02:03',
        controllerName: 'FarDriver 72530',
        bmsId: 'ANT:04:05:06',
        bmsName: 'ANT BMS 24S',
        createdAt: now,
      );

      final json = bike.toJson();
      expect(json['id'], 'bike_1');
      expect(json['name'], 'Arctic Leopard L1E');
      expect(json['controllerId'], 'FD:01:02:03');
      expect(json['bmsId'], 'ANT:04:05:06');

      final deserialized = BikeProfile.fromJson(json);
      expect(deserialized.id, bike.id);
      expect(deserialized.name, bike.name);
      expect(deserialized.controllerId, bike.controllerId);
      expect(deserialized.bmsId, bike.bmsId);
      expect(deserialized.hasBms, isTrue);

      final updated = bike.copyWith(name: 'Bike Frau');
      expect(updated.name, 'Bike Frau');
      expect(updated.controllerId, 'FD:01:02:03');
    });

    test('BikeSelectorNotifier saves, edits, and deletes bikes', () async {
      final storage = _BikeMemoryStorage();
      final dongle = t2.FakeDongleService();
      final container = ProviderContainer(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(dongle),
          storageServiceProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(bikeSelectorProvider.notifier);

      final bike1 = BikeProfile(
        id: 'b1',
        name: 'Mein Arctic',
        controllerId: 'FD:11:22',
        bmsId: 'ANT:33:44',
        createdAt: DateTime.now(),
      );

      await notifier.saveBike(bike1);
      var state = container.read(bikeSelectorProvider);
      expect(state.bikes, hasLength(1));
      expect(state.selectedBikeId, 'b1');
      expect(state.selectedBike?.name, 'Mein Arctic');

      final bike2 = BikeProfile(
        id: 'b2',
        name: 'Bike Frau',
        controllerId: 'FD:55:66',
        bmsId: 'ANT:77:88',
        createdAt: DateTime.now(),
      );

      await notifier.saveBike(bike2);
      state = container.read(bikeSelectorProvider);
      expect(state.bikes, hasLength(2));

      await notifier.setAutoConnectBike('b2');
      state = container.read(bikeSelectorProvider);
      expect(state.autoConnectBikeId, 'b2');
      expect(state.autoConnectBike?.name, 'Bike Frau');

      await notifier.deleteBike('b1');
      state = container.read(bikeSelectorProvider);
      expect(state.bikes, hasLength(1));
      expect(state.bikes.first.id, 'b2');
    });

    test('connectBike initiates parallel controller and BMS connections',
        () async {
      final storage = _BikeMemoryStorage();
      final dongle = t2.FakeDongleService();
      final fakeBms = _MockBmsService();

      final container = ProviderContainer(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(dongle),
          antBmsServiceProvider.overrideWithValue(fakeBms),
          storageServiceProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(bikeSelectorProvider.notifier);
      final bike = BikeProfile(
        id: 'b_test',
        name: 'Test Bike',
        controllerId: 'FD:AA:BB',
        bmsId: 'ANT:CC:DD',
        createdAt: DateTime.now(),
      );

      await notifier.connectBike(bike);
      expect(container.read(bikeSelectorProvider).selectedBikeId, 'b_test');
    });

    test('DualBleAutoConnect uses configured autoConnect bike', () {
      final storage = _BikeMemoryStorage();
      final dongle = t2.FakeDongleService();
      final fakeBms = _MockBmsService();

      final bike = BikeProfile(
        id: 'b_auto',
        name: 'Auto Bike',
        controllerId: 'FD:AUTO:01',
        bmsId: 'ANT:AUTO:02',
        createdAt: DateTime.now(),
      );
      storage.saveBike(bike);
      storage.saveAutoConnectBikeId('b_auto');

      final autoConnect = DualBleAutoConnect(storage, dongle, fakeBms);
      autoConnect.start();

      expect(storage.loadAutoConnectBikeId(), 'b_auto');
      expect(storage.loadBikes().first.controllerId, 'FD:AUTO:01');
    });
  });
}
