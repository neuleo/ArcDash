import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/controller_state.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/services/bluetooth_service.dart'
    show DongleConnectionState;
import 'package:arcdash/services/ble_transport.dart';
import 'package:arcdash/services/protocol_service.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:arcdash/utils/packet_parser.dart';
import 'package:arcdash/utils/packet_framer.dart';
import 'package:arcdash/services/diagnostic_log.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Override in ProviderScope');
});

class ControllerNotifier extends StateNotifier<ControllerState> {
  final BleTransport _bluetooth;
  final StorageService _storage;
  final DiagnosticLog _diagnostics;

  StreamSubscription? _dataSub;
  StreamSubscription? _connSub;

  final PacketFramer _framer = PacketFramer();

  // Keep a list of raw packets for the debug screen
  final List<String> _debugPackets = [];
  int _packetCount = 0;
  DateTime _lastPacketTime = DateTime.now();
  double _packetRate = 0.0;

  List<String> get debugPackets => List.unmodifiable(_debugPackets);
  double get packetRate => _packetRate;
  DiagnosticLog get diagnostics => _diagnostics;
  String exportDiagnosticJson() => _diagnostics.exportJson();

  ControllerNotifier(this._bluetooth, this._storage,
      {DiagnosticLog? diagnostics})
      : _diagnostics = diagnostics ?? DiagnosticLog(),
        super(ControllerState.initial()) {
    _connSub = _bluetooth.connectionStateStream.listen(_onConnectionState);
  }

  void _onConnectionState(DongleConnectionState cs) {
    _diagnostics.add(
      cs == DongleConnectionState.disconnected
          ? DiagnosticEventType.reconnect
          : DiagnosticEventType.connect,
      details: {'state': cs.name},
    );
    if (cs == DongleConnectionState.connected) {
      _onConnected();
    } else if (cs == DongleConnectionState.disconnected) {
      _dataSub?.cancel();
      _dataSub = null;
      _framer.reset();
    }
  }

  Future<void> _onConnected() async {
    // Subscribe to incoming data
    _dataSub = _bluetooth.rawDataStream.listen(_onRawData);

    // Send start-status-stream command
    await Future.delayed(const Duration(milliseconds: 200));
    await _bluetooth.write(ProtocolService.startStatusStreamPacket());
  }

  void _onRawData(List<int> chunk) {
    for (final packet in _framer.add(chunk)) {
      final parsed = PacketParser.parseStatusPacket(packet);
      if (parsed != null) {
        _processPacket(parsed, packet);
      } else {
        _diagnostics.add(DiagnosticEventType.parserError, details: {
          'length': packet.length,
          'reason': 'unsupported_frame',
        });
      }
    }
  }

  void _processPacket(ParsedPacket parsed, List<int> raw) {
    // Debug log (keep last 50)
    final hex = PacketParser.toHexString(raw);
    _debugPackets.add(
        '[0x${parsed.address.toRadixString(16).padLeft(2, '0').toUpperCase()}] $hex');
    _diagnostics.add(
      DiagnosticEventType.frame,
      details: {'address': parsed.address, 'length': raw.length, 'hex': hex},
    );
    if (_debugPackets.length > 50) _debugPackets.removeAt(0);

    // Packet rate calculation
    _packetCount++;
    final now = DateTime.now();
    final elapsed = now.difference(_lastPacketTime).inMilliseconds;
    if (elapsed >= 1000) {
      _packetRate = _packetCount * 1000.0 / elapsed;
      _packetCount = 0;
      _lastPacketTime = now;
    }

    // Extract telemetry
    final update = PacketParser.extractTelemetry(parsed);
    if (update == null) return;

    var next = state;

    if (update.measureSpeed != null) {
      final kph = _speedFromRaw(update.measureSpeed!);
      next = next.copyWith(speedKph: kph, lastUpdate: DateTime.now());
    }
    if (update.forward != null) next = next.copyWith(isForward: update.forward);
    if (update.reverse != null && update.reverse!) {
      next = next.copyWith(isForward: false);
    }
    if (update.gear != null) next = next.copyWith(gear: update.gear);
    if (update.brake != null) next = next.copyWith(isBraking: update.brake);
    if (update.motorHallError != null)
      next = next.copyWith(motorHallError: update.motorHallError);
    if (update.throttleError != null)
      next = next.copyWith(throttleError: update.throttleError);
    if (update.motorTempProtect != null)
      next = next.copyWith(motorTempProtect: update.motorTempProtect);
    if (update.controllerTempProtect != null)
      next = next.copyWith(controllerTempProtect: update.controllerTempProtect);

    if (update.voltageV != null)
      next = next.copyWith(voltageV: update.voltageV);
    if (update.currentA != null)
      next = next.copyWith(currentA: update.currentA);
    if (update.phaseACurrA != null)
      next = next.copyWith(phaseACurrA: update.phaseACurrA);
    if (update.phaseCCurrA != null)
      next = next.copyWith(phaseCCurrA: update.phaseCCurrA);
    if (update.motorTempC != null)
      next = next.copyWith(motorTempC: update.motorTempC);
    if (update.battCapPercent != null)
      next = next.copyWith(battCapPercent: update.battCapPercent);
    if (update.mosTempC != null)
      next = next.copyWith(controllerTempC: update.mosTempC);

    if (update.wheelRadius != null)
      next = next.copyWith(wheelRadius: update.wheelRadius);
    if (update.wheelWidth != null)
      next = next.copyWith(wheelWidth: update.wheelWidth);
    if (update.wheelRatio != null)
      next = next.copyWith(wheelRatio: update.wheelRatio);
    if (update.rateRatio != null && update.rateRatio! > 0)
      next = next.copyWith(rateRatio: update.rateRatio);

    if (update.maxSpeed != null)
      next = next.copyWith(maxSpeedRaw: update.maxSpeed);
    if (update.maxLineCurrRaw != null)
      next = next.copyWith(maxLineCurrRaw: update.maxLineCurrRaw);
    if (update.zeroBattCoeff != null)
      next = next.copyWith(zeroBattCoeff: update.zeroBattCoeff);
    if (update.fullBattCoeff != null)
      next = next.copyWith(fullBattCoeff: update.fullBattCoeff);

    // Recompute derived fields
    state = next.withComputedFields();

    // Save stock backup on first connect if not already done
    if (!_storage.firstConnectDone && update.maxLineCurrRaw != null) {
      _saveStockBackup();
    }
  }

  double _speedFromRaw(int measureSpeed) {
    if (state.rateRatio == 0) return 0.0;
    return measureSpeed *
        (0.00376991136 *
            (state.wheelRadius * 1270.0 + state.wheelWidth * state.wheelRatio) /
            state.rateRatio);
  }

  void _saveStockBackup() {
    final backup = <int, int>{
      0x15: state.maxSpeedRaw,
      0x19: state.maxLineCurrRaw,
    };
    _storage.saveStockBackup(backup);
  }

  Future<void> setRideMode(RideMode mode) async {
    if (state.speedKph > 2.0) {
      _diagnostics.add(DiagnosticEventType.safety, details: {
        'outcome': 'blocked',
        'reason': 'vehicle_moving',
      });
      return;
    }
    final packet =
        ProtocolService.setThrottleResponsePacket(mode.throttleResponseValue);
    final written = await _bluetooth.write(packet);
    _diagnostics.add(DiagnosticEventType.command, details: {
      'outcome': written ? 'transport_success' : 'transport_failure',
      'command': 'set_ride_mode',
    });
    if (!written) return;
    state = state.copyWith(rideMode: mode, lastUpdate: DateTime.now());
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}

final controllerProvider =
    StateNotifierProvider<ControllerNotifier, ControllerState>((ref) {
  final bluetooth = ref.watch(bluetoothServiceProvider);
  final storage = ref.watch(storageServiceProvider);
  return ControllerNotifier(bluetooth, storage);
});
