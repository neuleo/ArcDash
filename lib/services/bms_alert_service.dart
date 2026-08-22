import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/ant_bms_state.dart';
import 'package:arcdash/providers/ant_bms_provider.dart';

/// Severity levels for BMS alerts.
enum BmsAlertSeverity { info, warning, critical }

/// One active BMS alert condition.
class BmsAlert {
  final String ruleId;
  final BmsAlertSeverity severity;
  final String message;
  final DateTime firstSeenAt;

  const BmsAlert({
    required this.ruleId,
    required this.severity,
    required this.message,
    required this.firstSeenAt,
  });
}

/// Thresholds (see plan/15-temperatur-management.md, Feature 4).
const int kCellDeltaWarnMv = 50;
const int kCellUnderVoltageMv = 3200;
const int kCellOverVoltageMv = 4200;
const double kBmsTempHotC = 55.0;
const double kBmsTempColdC = 0.0;

/// Debounce window per rule: no duplicate alert within this period.
const Duration kAlertDebounce = Duration(seconds: 60);

class _RuleState {
  DateTime? lastFiredAt;
  bool active = false;
}

/// Evaluates every ANT-BMS frame against the warning rules and exposes the
/// currently active alerts as an immutable list. Each rule is debounced:
/// while a condition persists it stays active once, and re-fires at most
/// every [kAlertDebounce] after being cleared.
class BmsAlertNotifier extends StateNotifier<List<BmsAlert>> {
  BmsAlertNotifier(this._ref) : super(const []) {
    _sub = _ref!.listen<AntBmsState?>(antBmsStateProvider, (_, bms) {
      evaluate(bms);
    }, fireImmediately: true);
  }

  /// Test constructor without provider wiring.
  BmsAlertNotifier.forTest()
      : _ref = null,
        super(const []);

  final Ref? _ref;
  ProviderSubscription<AntBmsState?>? _sub;
  final Map<String, _RuleState> _rules = {};

  /// Core evaluation. Public via [evaluate] for testability.
  void evaluate(AntBmsState? bms) {
    if (bms == null) return;
    final now = DateTime.now();
    final fired = <BmsAlert>[];

    void check(String id, bool condition, BmsAlertSeverity severity,
        String Function(dynamic) message) {
      final rs = _rules.putIfAbsent(id, _RuleState.new);
      if (condition) {
        final debounced = rs.lastFiredAt != null &&
            now.difference(rs.lastFiredAt!) < kAlertDebounce &&
            !rs.active; // already-active alerts do not re-fire
        if (!debounced && (!rs.active || rs.lastFiredAt == null)) {
          rs.lastFiredAt = now;
          rs.active = true;
          fired.add(BmsAlert(
            ruleId: id,
            severity: severity,
            message: message(now),
            firstSeenAt: now,
          ));
        }
      } else {
        rs.active = false;
      }
    }

    // Rule 1: cell drift
    final delta = bms.cellDeltaMv;
    if (bms.cellCount > 0) {
      check(
        'cellDelta',
        delta > kCellDeltaWarnMv,
        BmsAlertSeverity.warning,
        (t) => 'Zellen driften auseinander ($delta mV)',
      );
    }

    // Rules 2/3: under-/overvoltage per cell
    if (bms.minCellVoltageMv != null) {
      final minV = bms.minCellVoltageMv!;
      final minIdx = bms.minCellIndex!;
      check(
        'cellUndervoltage',
        minV < kCellUnderVoltageMv,
        BmsAlertSeverity.critical,
        (t) => 'Zelle $minIdx tiefentladen (${minV} mV)',
      );
    }
    if (bms.maxCellVoltageMv != null) {
      final maxV = bms.maxCellVoltageMv!;
      final maxIdx = bms.maxCellIndex!;
      check(
        'cellOvervoltage',
        maxV > kCellOverVoltageMv,
        BmsAlertSeverity.critical,
        (t) => 'Zelle $maxIdx Überladung (${maxV} mV)',
      );
    }

    // Rules 4/5: temperature limits
    final validTemps =
        bms.temperaturesC.where((t) => t > -60 && t < 120).toList();
    if (validTemps.isNotEmpty) {
      final hottest = validTemps.reduce((a, b) => a > b ? a : b);
      final coldest = validTemps.reduce((a, b) => a < b ? a : b);
      check(
        'tempHot',
        hottest > kBmsTempHotC,
        BmsAlertSeverity.critical,
        (t) => 'Akku-Temperatur kritisch (${hottest.toStringAsFixed(1)} °C)',
      );
      check(
        'tempCold',
        coldest < kBmsTempColdC,
        BmsAlertSeverity.warning,
        (t) => 'Akku zu kalt (${coldest.toStringAsFixed(1)} °C) — Last und '
            'Rekuperation reduzieren',
      );
    }

    state = fired.isNotEmpty ? [...state, ...fired] : state;
  }

  /// Clears all active rules (called when BMS disconnects).
  void reset() {
    _rules.clear();
    state = const [];
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }
}

final bmsAlertProvider =
    StateNotifierProvider<BmsAlertNotifier, List<BmsAlert>>((ref) {
  return BmsAlertNotifier(ref);
});

/// Highest current alert severity for badge rendering (null = none active).
final bmsAlertBadgeProvider = Provider<BmsAlert?>((ref) {
  final alerts = ref.watch(bmsAlertProvider);
  if (alerts.isEmpty) return null;
  BmsAlert worst = alerts.first;
  for (final a in alerts.skip(1)) {
    if (a.severity.index > worst.severity.index) worst = a;
  }
  return worst;
});
