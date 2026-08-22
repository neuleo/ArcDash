import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/ant_bms_state.dart';
import 'package:arcdash/models/ride_log.dart';
import 'package:arcdash/providers/ant_bms_provider.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/services/gps_service.dart';

/// Records one [RideLogSample] per second while the controller is connected.
///
/// GPS fixes (position + altitude) are captured in parallel and stamped onto
/// each sample when fresh. Without GPS permission the log simply records null
/// GPS channels — recording never blocks on location.
///
/// The finished log persists under the key `ride_log_<id>` as JSON. Logs are
/// kept in memory for the session list and re-loaded lazily from storage.
class RideLogRecorder extends StateNotifier<RideLog?> {
  RideLogRecorder(this._ref) : super(null) {
    _connSub = _ref.listen<bool>(isConnectedProvider, (_, connected) {
      if (connected && !_recording) {
        start();
      } else if (!connected && _recording) {
        stop();
      }
    }, fireImmediately: true);

    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _sample());
  }

  final Ref _ref;
  Timer? _tick;
  ProviderSubscription<bool>? _connSub;
  StreamSubscription<GpsFix>? _gpsSub;
  GpsFix? _lastGpsFix;
  bool _recording = false;
  DateTime? _startedAt;

  void start() {
    if (_recording) return;
    _startedAt = DateTime.now();
    state = RideLog(
      id: 'log_${_startedAt!.millisecondsSinceEpoch}',
      startedAt: _startedAt!,
      endedAt: _startedAt!,
      samples: [],
    );
    _recording = true;
    _startGps();
  }

  /// Fire-and-forget GPS startup; failures never block ride logging.
  Future<void> _startGps() async {
    try {
      final gps = _ref.read(gpsServiceProvider);
      if (!await gps.start()) return;
      _lastGpsFix = await gps.lastKnown();
      await for (final fix in gps.stream) {
        _lastGpsFix = fix;
      }
    } catch (_) {/* GPS optional */}
  }

  /// Stops recording and persists the log to storage. Returns the id.
  String? stop() {
    if (!_recording || state == null) {
      _recording = false;
      return null;
    }
    _recording = false;
    final finished = state!;
    _persist(finished);
    // Keep the last finished log visible until the next ride starts.
    state = finished;
    return finished.id;
  }

  void _sample() {
    if (!_recording) return;
    final controller = _ref.read(controllerProvider);
    final bms = _ref.read(antBmsStateProvider);
    final gps = _lastGpsFix;
    final t = DateTime.now().difference(_startedAt!).inSeconds;

    var next = List<RideLogSample>.from(state!.samples);
    next.add(RideLogSample(
      t: t,
      speedKph: controller.speedKph,
      powerKw: controller.powerKw == 0 && !controller.isForward
          ? -controller.powerKw
          : controller.powerKw,
      voltageV: controller.voltageV > 0 ? controller.voltageV : null,
      currentA: controller.currentA,
      motorTempC: controller.motorTempC > 0 ? controller.motorTempC : null,
      controllerTempC:
          controller.controllerTempC > 0 ? controller.controllerTempC : null,
      socPercent: controller.battCapPercent > 0
          ? controller.battCapPercent.toDouble()
          : null,
      packVoltageV: bms != null && (bms.totalVoltageV ?? 0) > 0
          ? bms.totalVoltageV
          : null,
      bmsCurrentA: bms?.currentA,
      bmsTempC: _avgBmsTemp(bms),
      cellDeltaMv: bms != null && bms.cellCount > 0 ? bms.cellDeltaMv : null,
      gpsLatitude: gps?.latitude,
      gpsLongitude: gps?.longitude,
      gpsAltitudeM: gps?.altitudeMeters,
      gpsSpeedKph: gps?.speedKph,
      gpsAccuracyM: gps?.accuracyMeters,
    ));

    // Hard cap: keep the most recent window.
    if (next.length > RideLog.maxSamplesPerLog) {
      next = next.sublist(next.length - RideLog.maxSamplesPerLog);
    }

    state = state!.copyWithSamples(next);
  }

  double? _avgBmsTemp(AntBmsState? bms) {
    if (bms == null || bms.temperaturesC.isEmpty) return null;
    final valid = bms.temperaturesC.where((t) => t > -60 && t < 120).toList();
    if (valid.isEmpty) return null;
    return valid.reduce((a, b) => a + b) / valid.length;
  }

  void _persist(RideLog log) {
    try {
      final storage = _ref.read(storageServiceProvider).rangePredictionStorage;
      storage.write('ride_log_${log.id}', jsonEncode(log.toJson()));
    } catch (_) {
      // Persistence must never crash the recorder; log stays in memory.
    }
  }

  /// Loads a persisted log by id (for the ride history browser).
  RideLog? loadById(String id) {
    try {
      final storage = _ref.read(storageServiceProvider).rangePredictionStorage;
      final raw = storage.read('ride_log_$id');
      if (raw == null || raw.isEmpty) return null;
      return RideLog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _connSub?.close();
    _gpsSub?.cancel();
    super.dispose();
  }
}

extension on RideLog {
  RideLog copyWithSamples(List<RideLogSample> samples) => RideLog(
        id: id,
        startedAt: startedAt,
        endedAt: DateTime.now(),
        samples: samples,
      );
}

final rideLogRecorderProvider =
    StateNotifierProvider<RideLogRecorder, RideLog?>((ref) {
  return RideLogRecorder(ref);
});
