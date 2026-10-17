import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/controller_identity.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/tuning_provider.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:arcdash/services/write_safety.dart';

class _FakeDongle extends DongleService {
  final List<List<int>> written = [];
  final StreamController<List<int>> _raw = StreamController.broadcast();
  DongleConnectionState _state = DongleConnectionState.disconnected;
  String? _deviceId;
  String? _deviceName;

  @override
  DongleConnectionState get state => _state;

  @override
  String? get connectedDeviceId => _deviceId;

  @override
  String? get connectedDeviceName => _deviceName;

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

  void setConnected({required String id, required String name}) {
    _state = DongleConnectionState.connected;
    _deviceId = id;
    _deviceName = name;
  }

  void setDisconnected() {
    _state = DongleConnectionState.disconnected;
    _deviceId = null;
    _deviceName = null;
  }

  @override
  void dispose() {
    _raw.close();
  }
}

class _MemoryStorage extends StorageService {
  final Map<String, dynamic> _store = {};

  @override
  bool get hasStockBackup => true;

  @override
  List<TuningProfile> loadProfiles() => [];

  @override
  Future<void> saveProfile(TuningProfile profile) async {}

  @override
  Future<void> deleteProfile(String name) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Write Safety & Controller Identity Live Resolution', () {
    test('when disconnected, identity is incomplete and writes are blocked',
        () {
      final dongle = _FakeDongle()..setDisconnected();
      final container = ProviderContainer(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(dongle),
          storageServiceProvider.overrideWithValue(_MemoryStorage()),
        ],
      );
      addTearDown(container.dispose);

      final identity = container.read(controllerIdentityProvider);
      expect(identity.isComplete, isFalse);

      final decision = container.read(writeSafetyDecisionProvider);
      expect(decision.allowed, isFalse);
      expect(decision.rejections, contains(SafetyRejection.disconnected));
      expect(decision.rejections, contains(SafetyRejection.unknownIdentity));
    });

    test(
        'when connected to FarDriver, identity is verified and writes are allowed',
        () async {
      final dongle = _FakeDongle()
        ..setConnected(id: 'C0:02:6F:06:00:29', name: 'FarDriver BJ72V250AB');
      final container = ProviderContainer(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(dongle),
          storageServiceProvider.overrideWithValue(_MemoryStorage()),
        ],
      );
      addTearDown(container.dispose);

      // Verify identity resolution
      final identity = container.read(controllerIdentityProvider);
      expect(identity.isComplete, isTrue);
      expect(identity.model, 'FarDriver BJ72V250AB');
      expect(identity.bindingId, 'C0:02:6F:06:00:29');

      // Verify safety decision allows writing without any unknownIdentity error
      final decision = container.read(writeSafetyDecisionProvider);
      expect(decision.rejections,
          isNot(contains(SafetyRejection.unknownIdentity)));
      expect(
          decision.rejections, isNot(contains(SafetyRejection.missingBackup)));
      expect(decision.allowed, isTrue);

      // Test applyProfile succeeds without writeSafetyDecisionProvider override!
      final tuningNotifier = container.read(tuningProvider.notifier);
      final success = await tuningNotifier.applyProfile(saveToFlash: false);
      expect(success, isTrue);
      expect(dongle.written, isNotEmpty);
      expect(container.read(tuningProvider).appliedSuccessfully, isTrue);
      expect(container.read(tuningProvider).lastError, isNull);
    });
  });
}
