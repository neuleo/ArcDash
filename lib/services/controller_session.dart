import 'dart:async';

import 'package:arcdash/services/ble_transport.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/utils/packet_framer.dart';
import 'package:arcdash/utils/packet_parser.dart';

enum ControllerSessionState {
  idle,
  connecting,
  connected,
  disconnected,
  error,
}

class ControllerSessionSnapshot {
  final ControllerSessionState state;
  final TelemetryUpdate? telemetry;
  final String? error;

  const ControllerSessionSnapshot({
    required this.state,
    this.telemetry,
    this.error,
  });
}

class ControllerSession {
  final BleTransport _transport;
  final PacketFramer _framer = PacketFramer();
  final StreamController<ControllerSessionSnapshot> _updates =
      StreamController<ControllerSessionSnapshot>.broadcast(sync: true);
  late final StreamSubscription<DongleConnectionState> _stateSubscription;
  late final StreamSubscription<List<int>> _dataSubscription;

  ControllerSessionSnapshot _current = const ControllerSessionSnapshot(
    state: ControllerSessionState.idle,
  );
  bool _disposed = false;

  ControllerSession(this._transport) {
    _stateSubscription =
        _transport.connectionStateStream.listen(_onTransportState);
    _dataSubscription = _transport.rawDataStream.listen(_onBytes);
  }

  ControllerSessionSnapshot get current => _current;

  Stream<ControllerSessionSnapshot> watch() async* {
    yield _current;
    if (!_disposed) yield* _updates.stream;
  }

  Future<bool> connect(DiscoveredDongle dongle) async {
    if (_disposed) return false;
    if (_current.state == ControllerSessionState.connected) return true;
    _emit(const ControllerSessionSnapshot(
      state: ControllerSessionState.connecting,
    ));
    try {
      final connected = await _transport.connect(dongle);
      if (!connected) {
        _emit(const ControllerSessionSnapshot(
          state: ControllerSessionState.error,
          error: 'connect_failed',
        ));
      } else if (_current.state != ControllerSessionState.connected) {
        _emit(const ControllerSessionSnapshot(
          state: ControllerSessionState.connected,
        ));
      }
      return connected;
    } catch (_) {
      _emit(const ControllerSessionSnapshot(
        state: ControllerSessionState.error,
        error: 'connect_exception',
      ));
      return false;
    }
  }

  Future<void> disconnect() async {
    if (_disposed) return;
    await _transport.disconnect();
    if (!_disposed && _current.state != ControllerSessionState.disconnected) {
      _emit(const ControllerSessionSnapshot(
        state: ControllerSessionState.disconnected,
      ));
    }
  }

  void _onTransportState(DongleConnectionState state) {
    if (_disposed) return;
    final mapped = switch (state) {
      DongleConnectionState.connected => ControllerSessionState.connected,
      DongleConnectionState.connecting => ControllerSessionState.connecting,
      DongleConnectionState.disconnected => ControllerSessionState.disconnected,
      DongleConnectionState.error => ControllerSessionState.error,
      _ => ControllerSessionState.idle,
    };
    _emit(ControllerSessionSnapshot(
      state: mapped,
      telemetry: _current.telemetry,
    ));
  }

  void _onBytes(List<int> bytes) {
    if (_disposed) return;
    for (final packet in _framer.add(bytes)) {
      final parsed = PacketParser.parseStatusPacket(packet);
      if (parsed == null) continue;
      final telemetry = PacketParser.extractTelemetry(parsed);
      if (telemetry != null) {
        _emit(ControllerSessionSnapshot(
          state: _current.state,
          telemetry: telemetry,
        ));
      }
    }
  }

  void _emit(ControllerSessionSnapshot snapshot) {
    if (_disposed) return;
    _current = snapshot;
    _updates.add(snapshot);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stateSubscription.cancel();
    await _dataSubscription.cancel();
    await _updates.close();
  }
}
