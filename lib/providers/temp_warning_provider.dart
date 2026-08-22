import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/ant_bms_state.dart';
import 'package:arcdash/providers/ant_bms_provider.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/utils/battery_temp_power.dart';

/// Which temperature condition is currently violated.
enum TempWarningKind { none, tooCold, tooHot }

/// Immutable snapshot of the live temperature warning state.
class TempWarningState {
  final TempWarningKind kind;
  final double batteryTempC;

  /// Fine-grained allowed max power at the current pack temperature (kW).
  final double maxPowerKw;

  /// Percent of rated power currently available.
  final double availablePercentValue;

  /// Whether recuperation should be avoided (< 0 °C → lithium plating).
  final bool regenRisky;

  /// When true the user dismissed the banner; re-shows after cooldown.
  final bool dismissed;

  const TempWarningState({
    this.kind = TempWarningKind.none,
    this.batteryTempC = double.nan,
    this.maxPowerKw = 0,
    this.availablePercentValue = 100,
    this.regenRisky = false,
    this.dismissed = false,
  });

  bool get isActive => kind != TempWarningKind.none && !dismissed;
}

/// Cold threshold in °C. Below: full-screen cold warning.
const double kColdThresholdC = 0.0;

/// Hot threshold in °C. Above: full-screen hot warning.
const double kHotThresholdC = 55.0;

/// Hysteresis margin so the overlay does not flicker around a threshold.
const double kHysteresisC = 2.0;

/// Derives the temperature warning state from BMS NTC sensors with a
/// controller temperature fallback. Re-evaluates on every telemetry change
/// but applies hysteresis to avoid flapping right at the thresholds.
class TempWarningNotifier extends StateNotifier<TempWarningState> {
  TempWarningNotifier(this._ref) : super(const TempWarningState()) {
    _sub = _ref!.listen<AntBmsState?>(antBmsStateProvider, (_, bms) {
      _evaluate(bms);
    }, fireImmediately: true);
  }

  /// Test constructor: skips provider wiring entirely.
  TempWarningNotifier.forTest()
      : _ref = null,
        super(const TempWarningState());

  final Ref? _ref;
  ProviderSubscription<AntBmsState?>? _sub;
  Timer? _dismissTimer;
  TempWarningKind _latched = TempWarningKind.none;

  /// Effective battery temperature: prefer BMS NTC average, fall back to
  /// motor temperature reported by the controller when no BMS is attached.
  double? _batteryTemp(AntBmsState? bms) {
    if (bms != null && bms.temperaturesC.isNotEmpty) {
      final valid = bms.temperaturesC.where((t) => t > -60 && t < 120).toList();
      if (valid.isNotEmpty) {
        return valid.reduce((a, b) => a + b) / valid.length;
      }
    }
    return null;
  }

  void _evaluate(AntBmsState? bms) {
    final temp = _batteryTemp(bms);
    if (temp == null || temp.isNaN) {
      _latched = TempWarningKind.none;
      state = const TempWarningState();
      return;
    }

    // Determine active condition with hysteresis: once latched into a
    // warning we require the temperature to move kHysteresisC past the
    // opposite side before clearing.
    var kind = TempWarningKind.none;
    switch (_latched) {
      case TempWarningKind.tooCold:
        // stays cold until temp >= coldThreshold + hysteresis
        kind = temp < kColdThresholdC + kHysteresisC
            ? TempWarningKind.tooCold
            : TempWarningKind.none;
        break;
      case TempWarningKind.tooHot:
        kind = temp > kHotThresholdC - kHysteresisC
            ? TempWarningKind.tooHot
            : TempWarningKind.none;
        break;
      case TempWarningKind.none:
        if (temp < kColdThresholdC) {
          kind = TempWarningKind.tooCold;
        } else if (temp > kHotThresholdC) {
          kind = TempWarningKind.tooHot;
        }
        break;
    }
    _latched = kind;

    state = TempWarningState(
      kind: kind,
      batteryTempC: temp,
      maxPowerKw: maxPowerKwAt(temp),
      availablePercentValue: availablePercent(temp),
      regenRisky: isRegenRisky(temp),
      dismissed: state.dismissed && kind != TempWarningKind.none,
    );
  }

  /// User acknowledged the overlay; it hides for 5 minutes then returns
  /// while the underlying condition persists.
  void dismiss() {
    state = _copyWithDismissed(true);
    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(minutes: 5), () {
      if (mounted) state = _copyWithDismissed(false);
    });
  }

  /// Test seam: evaluate directly from a given BMS snapshot without waiting
  /// for the provider stream.
  void evaluateForTest(AntBmsState? bms) => _evaluate(bms);

  TempWarningState _copyWithDismissed(bool value) => TempWarningState(
        kind: state.kind,
        batteryTempC: state.batteryTempC,
        maxPowerKw: state.maxPowerKw,
        availablePercentValue: state.availablePercentValue,
        regenRisky: state.regenRisky,
        dismissed: value,
      );

  @override
  void dispose() {
    _sub?.close();
    _dismissTimer?.cancel();
    super.dispose();
  }
}

final tempWarningProvider =
    StateNotifierProvider<TempWarningNotifier, TempWarningState>((ref) {
  return TempWarningNotifier(ref);
});

/// True when the BLE link is up and telemetry is streaming — overlays are
/// suppressed without a live connection.
final hasLiveTelemetryProvider = Provider<bool>((ref) {
  return ref.watch(isConnectedProvider);
});
