import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/controller_state.dart';
import 'package:arcdash/models/fardriver_memory.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/tuning_provider.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/foreground_service_bridge.dart';
import 'package:arcdash/services/macrodroid_contract.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:arcdash/services/street_legal_trigger_service.dart';
import 'package:arcdash/services/write_safety.dart';

class _FakeDongleService extends DongleService {
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

  @override
  void dispose() {
    _raw.close();
  }
}

class _FakeForegroundBridge extends ForegroundServiceBridge {
  int successVibrations = 0;
  int errorVibrations = 0;
  String? lastNotification;

  @override
  Future<void> vibrateSuccess() async {
    successVibrations++;
  }

  @override
  Future<void> vibrateError() async {
    errorVibrations++;
  }

  @override
  Future<void> updateNotification(String text) async {
    lastNotification = text;
  }
}

class _MemoryStorage extends StorageService {
  @override
  bool get hasStockBackup => true;

  @override
  List<TuningProfile> loadProfiles() => [TuningProfile.stockOffroad()];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MacroDroid Street-Legal Trigger & Background Service Tests', () {
    late _FakeDongleService fakeDongle;
    late _FakeForegroundBridge fakeBridge;
    late _MemoryStorage storage;

    setUp(() {
      fakeDongle = _FakeDongleService();
      fakeBridge = _FakeForegroundBridge();
      storage = _MemoryStorage();
    });

    test(
        'rejects trigger with invalid action or extra parameters and vibrates error',
        () async {
      final container = ProviderContainer(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(fakeDongle),
          storageServiceProvider.overrideWithValue(storage),
          foregroundServiceBridgeProvider.overrideWithValue(fakeBridge),
        ],
      );
      addTearDown(container.dispose);

      final service = container.read(streetLegalTriggerServiceProvider);
      final result =
          await service.handleAction('com.arcdash.arcdash.INVALID_ACTION');

      expect(result, isFalse);
      expect(fakeBridge.errorVibrations, 1);
      expect(fakeBridge.successVibrations, 0);
    });

    test(
        'rejects trigger when safety decision is not allowed (moving or no backup)',
        () async {
      final container = ProviderContainer(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(fakeDongle),
          storageServiceProvider.overrideWithValue(storage),
          foregroundServiceBridgeProvider.overrideWithValue(fakeBridge),
          writeSafetyDecisionProvider.overrideWithValue(
            const SafetyDecision(
              allowed: false,
              rejections: {SafetyRejection.moving},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final service = container.read(streetLegalTriggerServiceProvider);
      final result = await service.handleAction(MacroDroidContract.action);

      expect(result, isFalse);
      expect(fakeBridge.errorVibrations, 1);
      expect(fakeBridge.successVibrations, 0);
    });

    test(
        'applies street legal when allowed, vibrates 2x and updates notification',
        () async {
      final container = ProviderContainer(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(fakeDongle),
          storageServiceProvider.overrideWithValue(storage),
          foregroundServiceBridgeProvider.overrideWithValue(fakeBridge),
          writeSafetyDecisionProvider.overrideWithValue(
            const SafetyDecision(allowed: true, rejections: {}),
          ),
        ],
      );
      addTearDown(container.dispose);

      final service = container.read(streetLegalTriggerServiceProvider);
      final result = await service.handleAction(MacroDroidContract.action);

      expect(result, isTrue);
      expect(fakeBridge.successVibrations, 1);
      expect(fakeBridge.errorVibrations, 0);
      expect(fakeBridge.lastNotification, 'Street Legal aktiv (45 km/h)');

      // Verify active profile is Street Legal
      final tuningState = container.read(tuningProvider);
      expect(tuningState.pendingProfile.name, 'Street Legal');
      expect(tuningState.pendingProfile.maxSpeedKph, 45);
      expect(tuningState.pendingProfile.maxLineCurrA, 80);
      expect(tuningState.pendingProfile.throttleResponse, 2); // ECO
    });
  });
}
