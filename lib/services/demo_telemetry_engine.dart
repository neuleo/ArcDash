import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/ant_bms_state.dart';
import 'package:arcdash/providers/temp_warning_provider.dart';

/// Demo scenarios that drive realistic telemetry curves for UI testing
/// without any BLE hardware.
enum DemoScenario {
  none('Aus'),
  city('Stadtverkehr'),
  mountain('Bergfahrt'),
  highway('Autobahn'),
  regen('Rekuperation'),
  coldBattery('Kalter Akku (-3°C)'),
  hotBattery('Heißer Akku (58°C)');

  final String label;
  const DemoScenario(this.label);
}

/// Fake ANT-BMS + temp-warning state generator. The controller-side fake
/// values are injected through [demoControllerOverrideProvider] by screens
/// that read the real provider; see demo_controller_provider below.
class DemoTelemetryEngine {
  DemoTelemetryEngine({required this.scenario, DateTime? now})
      : _start = now ?? DateTime.now();

  final DemoScenario scenario;
  final DateTime _start;
  final math.Random _rng = math.Random(42); // deterministic curves

  double _wave({
    required double amplitude,
    required double periodSeconds,
    required double offset,
    double phase = 0,
  }) {
    final t = DateTime.now().difference(_start).inMilliseconds / 1000.0;
    return offset +
        amplitude * math.sin(2 * math.pi * (t / periodSeconds) + phase) +
        0.15 * _rng.nextDouble() * amplitude * 0.1;
  }

  /// Seconds since demo start.
  int get elapsed => DateTime.now().difference(_start).inSeconds;

  // ---- Controller channels ----
  double speedKph() {
    switch (scenario) {
      case DemoScenario.city:
        // Stop-and-go between 0 and 45 km/h, ~40 s cycle.
        return math.max(0, _wave(amplitude: 24, periodSeconds: 40, offset: 22));
      case DemoScenario.mountain:
        return _wave(amplitude: 10, periodSeconds: 90, offset: 26);
      case DemoScenario.highway:
        return _wave(amplitude: 12, periodSeconds: 60, offset: 78);
      case DemoScenario.regen:
        // Deceleration ramps down from 55 to 5 repeatedly.
        final t = elapsed % 30;
        return math.max(3, 55 - t * 2.2);
      default:
        return 0;
    }
  }

  double powerKw() {
    switch (scenario) {
      case DemoScenario.city:
        return _wave(amplitude: 4.5, periodSeconds: 40, offset: 5.0);
      case DemoScenario.mountain:
        return 9.5 + _wave(amplitude: 1.8, periodSeconds: 45, offset: 0);
      case DemoScenario.highway:
        return 7.8 + _wave(amplitude: 2.2, periodSeconds: 60, offset: 0);
      case DemoScenario.regen:
        final t = elapsed % 30;
        // Negative power while decelerating hard in the first half.
        return t < 15 ? -(14.0 - t * 0.6) : 1.5;
      default:
        return 0;
    }
  }

  double voltageV() {
    switch (scenario) {
      case DemoScenario.mountain:
        return _wave(amplitude: 2.5, periodSeconds: 45, offset: 79.5);
      case DemoScenario.highway:
        return _wave(amplitude: 2.0, periodSeconds: 60, offset: 80.5);
      case DemoScenario.city:
        return _wave(amplitude: 1.5, periodSeconds: 40, offset: 82.0);
      case DemoScenario.regen:
        // Voltage rises during regen (charging).
        return 84.5 + _wave(amplitude: 1.2, periodSeconds: 30, offset: 0);
      default:
        return 83.7;
    }
  }

  double currentA() => powerKw() * 1000 / voltageV().clamp(50, 100);

  double motorTempC() {
    final base = scenario == DemoScenario.mountain ? 52.0 : 38.0;
    return base + elapsed * 0.01;
  }

  double controllerTempC() => motorTempC() - 6;

  int socPercent() {
    // Drains slowly over the demo run (~0.05 %/s when riding).
    final drain = scenario == DemoScenario.none ? 0 : elapsed * 0.05;
    return (91 - drain).floor().clamp(5, 100);
  }

  // ---- BMS channels ----
  AntBmsState bmsState() {
    final t = DateTime.now().difference(_start).inMilliseconds / 1000.0;
    final soc = socPercent();
    // Cell voltages around 4.18 V at high SOC, sagging under load.
    final loadSag =
        scenario == DemoScenario.none ? 0.0 : math.min(60, currentA()) * 0.0004;
    final baseMv = 3200 + (soc / 100.0) * 1000 - loadSag * 1000;
    final cells = List<int>.generate(20, (i) {
      final drift = math.sin(i * 1.7 + t / 25) *
          (scenario == DemoScenario.none ? 1 : 3.5);
      return (baseMv + drift).round();
    });
    final temps = List<double>.generate(3, (i) {
      final hot = scenario == DemoScenario.hotBattery
          ? 58.0
          : scenario == DemoScenario.coldBattery
              ? -3.0
              : 33.0;
      return hot + i * 0.7 + math.sin(t / 40 + i) * 0.3;
    });

    return AntBmsState(
      cellVoltagesMv: cells,
      temperaturesC: temps,
      mosfetTemperatureC: temps.first + 4,
      balancerTemperatureC: temps.first + 1,
      totalVoltageV: cells.fold<double>(0, (a, c) => a + c / 1000.0),
      currentA: -currentA(), // discharge positive per BMS convention varies
      socPercent: soc,
      sohPercent: 97,
      batteryStatusCode: scenario == DemoScenario.regen && powerKw() < -2
          ? 2 // charging
          : (scenario == DemoScenario.none ? 1 : 3), // static / discharging
      chargeMosfetStatus:
          scenario == DemoScenario.regen && powerKw() < -2 ? 1 : 0,
      dischargeMosfetStatus: scenario == DemoScenario.none ? 0 : 1,
      balancerStatus: deltaMv(cells) > 40 ? 1 : 0,
      capturedAt: DateTime.now(),
    );
  }

  static int deltaMv(List<int> cells) {
    if (cells.isEmpty) return 0;
    var min = cells.first;
    var max = cells.first;
    for (final c in cells.skip(1)) {
      if (c < min) min = c;
      if (c > max) max = c;
    }
    return max - min;
  }

  /// Temp warning evaluation input for overlay testing.
  TempWarningKind expectedWarningKind() {
    if (scenario == DemoScenario.coldBattery) return TempWarningKind.tooCold;
    if (scenario == DemoScenario.hotBattery) return TempWarningKind.tooHot;
    return TempWarningKind.none;
  }
}
