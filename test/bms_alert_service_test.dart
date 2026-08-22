import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/ant_bms_state.dart';
import 'package:arcdash/services/bms_alert_service.dart';

AntBmsState bmsWith({
  List<int>? cells,
  List<double>? temps,
}) {
  final base = AntBmsState.initial();
  return base.copyWith(
    cellVoltagesMv: cells ?? const [],
    temperaturesC: temps ?? const [],
  );
}

void main() {
  group('BmsAlertNotifier rules', () {
    late BmsAlertNotifier notifier;

    setUp(() {
      notifier = BmsAlertNotifier.forTest();
    });

    test('null BMS → no alerts', () {
      notifier.evaluate(null);
      expect(notifier.state, isEmpty);
    });

    test('balanced healthy pack (delta 4 mV) → no alerts', () {
      notifier.evaluate(bmsWith(cells: List.filled(20, 4184), temps: [25]));
      expect(notifier.state, isEmpty);
    });

    test('cell drift > 50 mV fires warning', () {
      // max 4200, min 4140 → delta 60 mV
      notifier.evaluate(bmsWith(cells: [4200, ...List.filled(18, 4195), 4140]));
      expect(notifier.state, hasLength(1));
      expect(notifier.state.first.ruleId, 'cellDelta');
      expect(notifier.state.first.severity, BmsAlertSeverity.warning);
      expect(notifier.state.first.message, contains('60 mV'));
    });

    test('cell drift at exactly 50 mV does NOT fire (> threshold)', () {
      notifier.evaluate(bmsWith(cells: [4200, ...List.filled(18, 4170), 4150]));
      expect(notifier.state.any((a) => a.ruleId == 'cellDelta'), isFalse);
    });

    test('undervoltage cell < 3200 mV fires critical', () {
      final cells = List<int>.filled(19, 3600).toList()..add(3150);
      notifier.evaluate(bmsWith(cells: cells));
      final alert =
          notifier.state.firstWhere((a) => a.ruleId == 'cellUndervoltage');
      expect(alert.severity, BmsAlertSeverity.critical);
      expect(alert.message, contains('Zelle 20'));
      expect(alert.message, contains('3150 mV'));
    });

    test('overvoltage cell > 4200 mV fires critical', () {
      final cells = List<int>.filled(19, 4180).toList()..add(4210);
      notifier.evaluate(bmsWith(cells: cells));
      final alert =
          notifier.state.firstWhere((a) => a.ruleId == 'cellOvervoltage');
      expect(alert.severity, BmsAlertSeverity.critical);
      expect(alert.message, contains('Zelle 20'));
      expect(alert.message, contains('4210 mV'));
    });

    test('hot NTC > 55 °C fires critical', () {
      notifier
          .evaluate(bmsWith(cells: List.filled(20, 4180), temps: [30.0, 56.5]));
      final alert = notifier.state.firstWhere((a) => a.ruleId == 'tempHot');
      expect(alert.severity, BmsAlertSeverity.critical);
      expect(alert.message, contains('56.5'));
    });

    test('cold NTC < 0 °C fires warning with regen hint', () {
      notifier.evaluate(bmsWith(cells: List.filled(20, 4180), temps: [-3.2]));
      final alert = notifier.state.firstWhere((a) => a.ruleId == 'tempCold');
      expect(alert.severity, BmsAlertSeverity.warning);
      expect(alert.message, contains('-3.2'));
      expect(alert.message, contains('Rekuperation'));
    });

    test('invalid sensor values are ignored', () {
      notifier.evaluate(
          bmsWith(cells: List.filled(20, 4180), temps: [-999.0, 999.0]));
      expect(notifier.state, isEmpty);
    });

    test('multiple violations fire multiple distinct rules', () {
      notifier.evaluate(bmsWith(
          cells: [4250, ...List.filled(18, 4100), 3100], temps: [58.0]));
      final ids = notifier.state.map((a) => a.ruleId).toSet();
      expect(ids, containsAll(['cellDelta', 'cellUndervoltage', 'tempHot']));
    });

    test('persistent condition stays active without duplicate spam', () {
      final badPack = bmsWith(cells: [4200, ...List.filled(18, 4195), 4140]);
      notifier.evaluate(badPack);
      final countAfterFirst =
          notifier.state.where((a) => a.ruleId == 'cellDelta').length;
      expect(countAfterFirst, 1);

      // Same condition again immediately → no duplicate while active.
      notifier.reset(); // clears active list but keeps rule state? No:
      // reset() also clears rule memory; emulate continuous monitoring:
      final n2 = BmsAlertNotifier.forTest();
      n2.evaluate(badPack);
      n2.evaluate(badPack);
      expect(n2.state.where((a) => a.ruleId == 'cellDelta'), hasLength(1));
    });

    test('reset clears everything', () {
      final cells = List<int>.filled(19, 3600).toList()..add(3100);
      notifier.evaluate(bmsWith(cells: cells));
      expect(notifier.state, isNotEmpty);
      notifier.reset();
      expect(notifier.state, isEmpty);
    });
  });

  group('badge severity', () {
    test('worst severity wins', () {
      // Directly verify severity ordering logic used by the badge provider.
      expect(BmsAlertSeverity.info.index,
          lessThan(BmsAlertSeverity.warning.index));
      expect(BmsAlertSeverity.warning.index,
          lessThan(BmsAlertSeverity.critical.index));
    });
  });
}
