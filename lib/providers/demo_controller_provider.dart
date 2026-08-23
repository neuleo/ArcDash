import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/controller_state.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/demo_mode_provider.dart'
    show DemoModeState, demoModeProvider, demoControllerSnapshot;
import 'package:arcdash/services/demo_telemetry_engine.dart';

/// Live fake ControllerState while demo mode is active, otherwise null.
///
/// A 1 Hz ticker drives the [DemoTelemetryEngine] and publishes a full
/// snapshot each second so the cockpit tiles (speed, power, temps, SOC)
/// animate without any BLE hardware.
class _DemoControllerTicker extends StateNotifier<ControllerState?> {
  _DemoControllerTicker(this._ref) : super(null) {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _sub = _ref.listen<DemoModeState>(demoModeProvider, (prev, next) {
      if (!next.active) {
        _engine = null;
        state = null;
      } else if (_engine == null || prev?.scenario != next.scenario) {
        _engine = DemoTelemetryEngine(scenario: next.scenario);
        _tick(); // publish first sample immediately
      }
    }, fireImmediately: true);
    // If demo was already enabled before this provider was constructed
    // (e.g. user toggled in Dev Tools, then opened the cockpit), the
    // fireImmediately callback above already started the engine.
  }

  final Ref _ref;
  Timer? _timer;
  ProviderSubscription<DemoModeState>? _sub;
  DemoTelemetryEngine? _engine;

  void _tick() {
    final engine = _engine;
    if (engine == null || !_ref.read(demoModeProvider).active) return;
    try {
      state = demoControllerSnapshot(engine);
    } catch (_) {
      // Never let a bad sample kill the ticker; retry next second.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.close();
    super.dispose();
  }
}

final demoControllerProvider =
    StateNotifierProvider<_DemoControllerTicker, ControllerState?>((ref) {
  return _DemoControllerTicker(ref);
});

/// The effective ControllerState for UI consumers: demo data when active,
/// real BLE data otherwise. Cockpit tiles should watch THIS provider.
/// Tests override [controllerProvider] (the real source) freely.
final effectiveControllerProvider = Provider<ControllerState>((ref) {
  final demoActive = ref.watch(demoModeProvider).active;
  if (demoActive) {
    final fake = ref.watch(demoControllerProvider);
    if (fake != null) return fake;
  }
  return ref.watch(controllerProvider);
});
