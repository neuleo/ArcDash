import 'dart:async';
import 'dart:io';

import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/tuning_provider.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/heb_file_parser.dart';
import 'package:arcdash/services/protocol_service.dart';
import 'package:arcdash/services/stock_heb_restore.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:arcdash/services/write_safety.dart';
import 'package:arcdash/utils/crc_calculator.dart';
import 'package:arcdash/utils/tuning_conversions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory StorageService used to exercise the preset persistence without
/// platform channels. Keeps the stock backup flag set so a write can pass the
/// fail-closed evaluation in tests.
class MemoryStorage extends StorageService {
  final List<TuningProfile> profiles = [];

  @override
  bool get hasStockBackup => true;

  @override
  List<TuningProfile> loadProfiles() => List.unmodifiable(profiles);

  @override
  Future<void> saveProfile(TuningProfile profile) async {
    final index = profiles.indexWhere((p) => p.name == profile.name);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.add(profile);
    }
  }

  @override
  Future<void> deleteProfile(String name) async {
    profiles.removeWhere((p) => p.name == name);
  }
}

class FakeDongleService extends DongleService {
  final List<List<int>> written = [];
  final StreamController<List<int>> _raw = StreamController.broadcast();

  DongleConnectionState _state = DongleConnectionState.connected;

  set stateOverride(DongleConnectionState value) => _state = value;

  @override
  DongleConnectionState get state => _state;

  @override
  Stream<DongleConnectionState> get connectionStateStream =>
      Stream.value(_state).distinct();

  @override
  Stream<List<int>> get rawDataStream => _raw.stream;

  @override
  Stream<List<DiscoveredDongle>> get scanResultsStream => const Stream.empty();

  @override
  Future<bool> write(List<int> data) async {
    written.add(List<int>.from(data));
    return true;
  }

  void emit(List<int> packet) {
    _raw.add(packet);
  }

  @override
  void dispose() {
    _raw.close();
  }
}

ProviderContainer _container({
  DongleService? dongle,
  StorageService? storage,
}) {
  return ProviderContainer(
    overrides: [
      bluetoothServiceProvider.overrideWithValue(dongle ?? FakeDongleService()),
      storageServiceProvider.overrideWithValue(storage ?? MemoryStorage()),
      writeSafetyDecisionProvider.overrideWithValue(
        const SafetyDecision(allowed: true, rejections: {}),
      ),
    ],
  );
}

List<int> _readHebBytes() {
  final file = File('assets/basemaps/unmodified_basemap.heb');
  if (!file.existsSync()) {
    throw StateError('missing asset ${file.path}');
  }
  return file.readAsBytesSync();
}

void main() {
  group('T090/T091 - factory presets', () {
    test('factory presets match the T091 specification', () {
      final presets = TuningProfile.factoryPresets();
      expect(
          presets.map((p) => p.name), ['Stock Offroad', 'Eco Range', 'Custom']);

      final stock = TuningProfile.stockOffroad();
      expect(stock.maxSpeedKph, 125);
      expect(stock.maxLineCurrA, 200);
      expect(stock.throttleResponse, 1);
      expect(stock.isStock, isTrue);

      final eco = TuningProfile.ecoRange();
      expect(eco.maxSpeedKph, 45);
      expect(eco.maxLineCurrA, 100);
      expect(eco.throttleResponse, 2);
      expect(eco.isStock, isTrue);
    });

    test('TuningConversions map SI values to the confirmed raw ranges', () {
      expect(TuningConversions.maxSpeedKphToRaw(125), 9000);
      expect(TuningConversions.maxSpeedKphToRaw(65), 4680);
      expect(TuningConversions.maxLineCurrAToRaw(180), 720);
      expect(TuningConversions.maxLineCurrAToRaw(100), 400);
      expect(TuningConversions.throttleResponseToRaw(1), 0x04);
      expect(TuningConversions.throttleResponseToRaw(2), 0x08);
    });

    test('TuningProfile JSON round trip preserves saved custom presets', () {
      final profile =
          TuningProfile.custom().copyWith(name: 'My Trail', isStock: false);
      final decoded = TuningProfile.fromJsonString(profile.toJsonString());
      expect(decoded.name, 'My Trail');
      expect(decoded.isStock, isFalse);
      expect(decoded.maxSpeedKph, profile.maxSpeedKph);
      expect(decoded.powerCurve, hasLength(3));
    });

    test('saveCurrentProfile persists the pending values as a custom preset',
        () async {
      final storage = MemoryStorage();
      final container = _container(storage: storage);
      addTearDown(container.dispose);
      final notifier = container.read(tuningProvider.notifier);

      notifier.loadPreset(TuningProfile.ecoRange());
      await notifier.saveCurrentProfile('My Trail');

      final state = container.read(tuningProvider);
      expect(state.savedProfiles, hasLength(1));
      final saved = state.savedProfiles.first;
      expect(saved.name, 'My Trail');
      expect(saved.isStock, isFalse);
      expect(saved.maxSpeedKph, 45);
      expect(saved.maxLineCurrA, 100);
      expect(storage.loadProfiles(), hasLength(1));
    });

    test('saveCurrentProfile overwrites a name with the same key', () async {
      final storage = MemoryStorage();
      final container = _container(storage: storage);
      addTearDown(container.dispose);
      final notifier = container.read(tuningProvider.notifier);

      notifier.loadPreset(TuningProfile.ecoRange());
      await notifier.saveCurrentProfile('My Trail');
      await notifier.saveCurrentProfile('My Trail');
      expect(container.read(tuningProvider).savedProfiles, hasLength(1));
    });

    test(
        'deleteProfile removes a custom preset and reselects Custom when it '
        'was active', () async {
      final storage = MemoryStorage();
      final container = _container(storage: storage);
      addTearDown(container.dispose);
      final notifier = container.read(tuningProvider.notifier);

      await notifier.saveCurrentProfile('My Trail');
      notifier.loadPreset(container.read(tuningProvider).savedProfiles.first);
      expect(container.read(tuningProvider).pendingProfile.name, 'My Trail');

      await notifier.deleteProfile('My Trail');
      final state = container.read(tuningProvider);
      expect(state.savedProfiles, isEmpty);
      expect(state.pendingProfile.name, 'Custom');
    });
  });

  group('T090 - live write engine', () {
    test('applyProfile writes the three tunable registers when allowed',
        () async {
      final dongle = FakeDongleService();
      final container = _container(dongle: dongle);
      addTearDown(container.dispose);
      final notifier = container.read(tuningProvider.notifier);

      notifier.loadPreset(TuningProfile.custom());
      final ok = await notifier.applyProfile();

      expect(ok, isTrue);
      expect(container.read(tuningProvider).appliedSuccessfully, isTrue);
      expect(container.read(tuningProvider).lastError, isNull);
      expect(dongle.written, [
        ProtocolService.buildWritePacket(
          0x15,
          TuningConversions.maxSpeedKphToRaw(65),
        ),
        ProtocolService.buildWritePacket(
          0x19,
          TuningConversions.maxLineCurrAToRaw(100),
        ),
        ProtocolService.buildWritePacket(
          0x1A,
          TuningConversions.throttleResponseToRaw(1),
        ),
      ]);
    });

    test('applyProfile fails closed and writes nothing when safety rejects',
        () async {
      final dongle = FakeDongleService();
      final container = ProviderContainer(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(dongle),
          storageServiceProvider.overrideWithValue(MemoryStorage()),
          writeSafetyDecisionProvider.overrideWithValue(
            const SafetyDecision(
              allowed: false,
              rejections: {SafetyRejection.moving},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(tuningProvider.notifier);

      final ok = await notifier.applyProfile();
      expect(ok, isFalse);
      expect(container.read(tuningProvider).appliedSuccessfully, isFalse);
      expect(container.read(tuningProvider).lastError, isNotNull);
      expect(dongle.written, isEmpty);
    });

    test('applyProfile reports a failed transport write', () async {
      final dongle = _FailingDongleService();
      final container = _container(dongle: dongle);
      addTearDown(container.dispose);
      final notifier = container.read(tuningProvider.notifier);

      final ok = await notifier.applyProfile();
      expect(ok, isFalse);
      expect(container.read(tuningProvider).lastError,
          contains('not acknowledged'));
    });
  });

  group('T092 - Stock HEB restore', () {
    test('planner expands the factory basemap into 156 register writes', () {
      final heb = HebFile.parse(_readHebBytes());
      final plan = const StockHebRestorePlanner().plan(heb);

      expect(plan.writes, hasLength(HebFile.blockAddresses.length * 6));
      final maxSpeed = plan.writes.firstWhere((w) => w.address == 0x15);
      final lineCurr = plan.writes.firstWhere((w) => w.address == 0x19);
      expect(maxSpeed.value, 9000);
      expect(lineCurr.value, 720);

      for (final write in plan.writes) {
        final packet = write.toPacket();
        expect(packet, hasLength(8));
        expect(packet[0], 0xAA);
        expect(packet[2], write.address & 0xFF);
        expect(packet[4], write.value & 0xFF);
        expect(packet[5], (write.value >> 8) & 0xFF);
        expect(CrcCalculator.verifyCRC(packet, 8), isTrue);
      }
    });

    test('restoreStock writes every factory register when allowed', () async {
      final dongle = FakeDongleService();
      final container = _container(dongle: dongle);
      addTearDown(container.dispose);
      final notifier = container.read(tuningProvider.notifier);

      final ok = await notifier.restoreStock(basemapBytes: _readHebBytes());
      expect(ok, isTrue);
      expect(container.read(tuningProvider).appliedSuccessfully, isTrue);
      expect(dongle.written.length, 156);
      expect(
        dongle.written.first,
        ProtocolService.buildWritePacket(
          0x00,
          0x00 | (0x01 << 8),
        ),
      );
    });

    test('restoreStock fails closed when safety rejects', () async {
      final dongle = FakeDongleService();
      final container = ProviderContainer(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(dongle),
          storageServiceProvider.overrideWithValue(MemoryStorage()),
          writeSafetyDecisionProvider.overrideWithValue(
            const SafetyDecision(
              allowed: false,
              rejections: {SafetyRejection.missingBackup},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(tuningProvider.notifier);

      final ok = await notifier.restoreStock(basemapBytes: _readHebBytes());
      expect(ok, isFalse);
      expect(dongle.written, isEmpty);
      expect(container.read(tuningProvider).lastError, isNotNull);
    });

    test('restoreStock rejects malformed basemap bytes', () async {
      final dongle = FakeDongleService();
      final container = _container(dongle: dongle);
      addTearDown(container.dispose);
      final notifier = container.read(tuningProvider.notifier);

      final ok = await notifier.restoreStock(basemapBytes: List.filled(10, 0));
      expect(ok, isFalse);
      expect(
          container.read(tuningProvider).lastError, contains('Restore failed'));
    });
  });
}

class _FailingDongleService extends DongleService {
  @override
  DongleConnectionState get state => DongleConnectionState.connected;

  @override
  Stream<DongleConnectionState> get connectionStateStream =>
      const Stream.empty();

  @override
  Stream<List<int>> get rawDataStream => const Stream.empty();

  @override
  Stream<List<DiscoveredDongle>> get scanResultsStream => const Stream.empty();

  @override
  Future<bool> write(List<int> data) async => false;

  @override
  void dispose() {}
}
