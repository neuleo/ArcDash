import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/ant_bms_state.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart'
    show storageServiceProvider;
import 'package:arcdash/services/ant_bms_service.dart';
import 'package:arcdash/services/bluetooth_service.dart'
    show DongleConnectionState, DiscoveredDongle;
import 'package:arcdash/services/diagnostic_log.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:arcdash/utils/ant_bms_parser.dart';

/// Shared ANT BMS service instance (independent of the controller dongle).
final antBmsServiceProvider = Provider<AntBmsService>((ref) {
  final diagnostics = ref.watch(diagnosticsLogProvider);
  final service = AntBmsService(diagnostics: diagnostics);
  ref.onDispose(service.dispose);
  return service;
});

final antBmsConnectionStateProvider = StreamProvider<DongleConnectionState>(
    (ref) => ref.watch(antBmsServiceProvider).connectionStateStream);

final isBmsConnectedProvider = Provider<bool>((ref) {
  final state = ref.watch(antBmsConnectionStateProvider).valueOrNull;
  return state == DongleConnectionState.connected;
});

final antBmsDeviceNameProvider = Provider<String?>((ref) {
  final service = ref.watch(antBmsServiceProvider);
  ref.watch(antBmsConnectionStateProvider);
  return service.connectedDeviceName;
});

/// Keeps the ANT BMS session alive, polls the status register and decodes
/// status frames into an [AntBmsState].
class AntBmsNotifier extends StateNotifier<AntBmsState?> {
  final AntBmsService _service;
  final StorageService _storage;
  final DiagnosticLog _diagnostics;

  final AntBmsFramer _framer = AntBmsFramer();
  StreamSubscription<DongleConnectionState>? _connSub;
  StreamSubscription<List<int>>? _dataSub;
  Timer? _pollTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  String? _lastConnectedId;

  AntBmsNotifier(this._service, this._storage, {DiagnosticLog? diagnostics})
      : _diagnostics = diagnostics ?? DiagnosticLog(),
        super(AntBmsState.initial()) {
    _connSub = _service.connectionStateStream.listen(_onConnectionState);
    if (_service.state == DongleConnectionState.connected) {
      _onConnected();
    }
    _autoReconnectRemembered();
  }

  /// Dual-BLE auto-remember: silently reconnects the last known BMS when the
  /// app starts.
  void _autoReconnectRemembered() {
    final remembered = _storage.loadLastBmsId();
    if (remembered == null || remembered.isEmpty) return;
    if (_service.state == DongleConnectionState.connected) return;
    unawaited(_service.connectById(remembered, name: 'ANT BMS (gemerkt)'));
  }

  void _onConnectionState(DongleConnectionState cs) {
    _diagnostics.add(
      cs == DongleConnectionState.disconnected
          ? DiagnosticEventType.reconnect
          : DiagnosticEventType.connect,
      details: {'bms': true, 'state': cs.name},
    );
    if (cs == DongleConnectionState.connected) {
      _onConnected();
    } else if (cs == DongleConnectionState.disconnected) {
      _pollTimer?.cancel();
      _pollTimer = null;
      _dataSub?.cancel();
      _dataSub = null;
      _framer.reset();
      state = null;
      _scheduleReconnect();
    }
  }

  Future<void> _onConnected() async {
    _dataSub = _service.rawDataStream.listen(_onRawData);
    _lastConnectedId = _service.connectedDeviceId;
    if (_lastConnectedId != null) {
      unawaited(_storage.saveLastBmsId(_lastConnectedId!));
    }
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _service.write(AntBmsParser.buildStatusRequest());
    });
    await _service.write(AntBmsParser.buildStatusRequest());
  }

  void _scheduleReconnect() {
    if (_lastConnectedId == null) return;
    if (_reconnectAttempts >= 5) return;
    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      unawaited(_service.connectById(_lastConnectedId!));
    });
  }

  void _onRawData(List<int> chunk) {
    for (final frame in _framer.add(chunk)) {
      if (AntBmsParser.verifyCrc(frame)) {
        final parsed = AntBmsParser.parseStatusFrame(frame);
        if (parsed != null) {
          state = parsed;
          continue;
        }
      }
      _diagnostics.add(DiagnosticEventType.parserError, details: {
        'bms': true,
        'length': frame.length,
        'reason': 'invalid_bms_frame',
      });
    }
  }

  void requestStatus() {
    unawaited(_service.write(AntBmsParser.buildStatusRequest()));
  }

  Future<void> connect(DiscoveredDongle dongle) async {
    final ok = await _service.connect(dongle);
    if (ok) {
      unawaited(_storage.saveLastBmsId(_service.connectedDeviceId!));
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    _dataSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}

final antBmsStateProvider =
    StateNotifierProvider<AntBmsNotifier, AntBmsState?>((ref) {
  final service = ref.watch(antBmsServiceProvider);
  final storage = ref.watch(storageServiceProvider);
  final diagnostics = ref.watch(diagnosticsLogProvider);
  return AntBmsNotifier(service, storage, diagnostics: diagnostics);
});
