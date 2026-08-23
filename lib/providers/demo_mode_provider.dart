import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/ant_bms_state.dart';
import 'package:arcdash/models/controller_state.dart';
import 'package:arcdash/providers/ant_bms_provider.dart';
import 'package:arcdash/providers/temp_warning_provider.dart';
import 'package:arcdash/services/demo_telemetry_engine.dart';
import 'package:arcdash/utils/battery_temp_power.dart'
    show availablePercent, maxPowerKwAt;

/// Thin wrappers so the effective-warning builder stays testable.
double availablePercentOf(double t) => availablePercent(t);
double maxKwAtTemp(double t) => maxPowerKwAt(t);

/// Whether demo mode is enabled and which scenario is running.
class DemoModeState {
  final bool active;
  final DemoScenario scenario;

  const DemoModeState({this.active = false, this.scenario = DemoScenario.none});

  DemoModeState copyWith({bool? active, DemoScenario? scenario}) =>
      DemoModeState(
        active: active ?? this.active,
        scenario: scenario ?? this.scenario,
      );
}

/// Master switch + scenario selection for demo mode. Persisted per session
/// only (never survives a restart — you never want to ride on fake data).
class DemoModeNotifier extends StateNotifier<DemoModeState> {
  DemoModeNotifier() : super(const DemoModeState());

  void enable(DemoScenario scenario) {
    if (scenario == DemoScenario.none) {
      state = const DemoModeState();
      return;
    }
    state = DemoModeState(active: true, scenario: scenario);
  }

  void setScenario(DemoScenario scenario) => enable(scenario);

  void disable() => state = const DemoModeState();
}

final demoModeProvider =
    StateNotifierProvider<DemoModeNotifier, DemoModeState>((ref) {
  return DemoModeNotifier();
});

/// Live fake BMS state while demo mode is active, otherwise null so the real
/// provider value passes through untouched.
final demoBmsProvider =
    StateNotifierProvider<_DemoBmsTicker, AntBmsState?>((ref) {
  return _DemoBmsTicker(ref);
});

class _DemoBmsTicker extends StateNotifier<AntBmsState?> {
  _DemoBmsTicker(this._ref) : super(null) {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _sub = _ref.listen<DemoModeState>(demoModeProvider, (prev, next) {
      if (!next.active) {
        _engine = null;
        state = null;
      } else if (_engine == null || prev?.scenario != next.scenario) {
        _engine = DemoTelemetryEngine(scenario: next.scenario);
      }
    }, fireImmediately: true);
  }

  final Ref _ref;
  Timer? _timer;
  ProviderSubscription<DemoModeState>? _sub;
  DemoTelemetryEngine? _engine;

  void _tick() {
    final engine = _engine;
    if (engine == null || !_ref.read(demoModeProvider).active) return;
    state = engine.bmsState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.close();
    super.dispose();
  }
}

/// The effective BMS state for UI consumers: demo data when active,
/// real BLE data otherwise.
final effectiveBmsProvider = Provider<AntBmsState?>((ref) {
  final demoActive = ref.watch(demoModeProvider).active;
  if (demoActive) return ref.watch(demoBmsProvider);
  return ref.watch(antBmsStateProvider);
});

/// Effective temp-warning overlay state derived from either demo or live BMS.
final effectiveTempWarningProvider = Provider<TempWarningState>((ref) {
  final demoActive = ref.watch(demoModeProvider).active;
  if (!demoActive) return ref.watch(tempWarningProvider);

  final bms = ref.watch(demoBmsProvider);
  if (bms == null || bms.temperaturesC.isEmpty) {
    return const TempWarningState();
  }
  final temps = bms.temperaturesC;
  final avg = temps.reduce((a, b) => a + b) / temps.length;

  TempWarningKind kind;
  if (avg < kColdThresholdC) {
    kind = TempWarningKind.tooCold;
  } else if (avg > kHotThresholdC) {
    kind = TempWarningKind.tooHot;
  } else {
    kind = TempWarningKind.none;
  }

  // Reuse the fine-grained power model from battery_temp_power via provider.
  double percent = 100;
  double maxKw = 0;
  switch (kind) {
    case TempWarningKind.tooCold:
    case TempWarningKind.tooHot:
      percent = availablePercentOf(avg);
      maxKw = maxKwAtTemp(avg);
      break;
    case TempWarningKind.none:
      break;
  }

  return TempWarningState(
    kind: kind,
    batteryTempC: avg,
    maxPowerKw: maxKw,
    availablePercentValue: percent,
    regenRisky: avg < kColdThresholdC,
  );
});

/// A synthetic ControllerState snapshot for demo rides (dashboard tiles that
/// read ControllerState directly can consume this when demo is active).
ControllerState demoControllerSnapshot(DemoTelemetryEngine e) =>
    ControllerState(
      speedKph: e.speedKph(),
      powerKw: e.powerKw().abs(),
      voltageV: e.voltageV(),
      currentA: e.currentA().abs(),
      motorTempC: e.motorTempC(),
      controllerTempC: e.controllerTempC(),
      battCapPercent: e.socPercent(),
      isForward: e.powerKw() >= -1,
      isBraking: e.powerKw() < -2,
      lastUpdate: DateTime.now(),
    );
