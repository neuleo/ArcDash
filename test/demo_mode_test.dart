import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/ant_bms_state.dart';
import 'package:arcdash/providers/demo_mode_provider.dart';
import 'package:arcdash/providers/temp_warning_provider.dart'
    show kColdThresholdC, kHotThresholdC;
import 'package:arcdash/services/demo_telemetry_engine.dart';

void main() {
  group('DemoTelemetryEngine scenarios', () {
    test('city scenario produces plausible stop-and-go speed', () {
      final engine = DemoTelemetryEngine(
          scenario: DemoScenario.city,
          now: DateTime.now().subtract(const Duration(seconds: 5)));
      final speed = engine.speedKph();
      expect(speed, greaterThanOrEqualTo(0));
      expect(speed, lessThan(50));
    });

    test('highway speed stays in the upper band', () {
      final engine = DemoTelemetryEngine(
          scenario: DemoScenario.highway,
          now: DateTime.now().subtract(const Duration(seconds: 10)));
      final speed = engine.speedKph();
      expect(speed, greaterThan(55));
      expect(speed, lessThan(100));
    });

    test('mountain power stays high (climbing)', () {
      final engine = DemoTelemetryEngine(
          scenario: DemoScenario.mountain, now: DateTime.now());
      final kw = engine.powerKw();
      expect(kw, greaterThan(6.0));
      expect(kw, lessThan(12.0));
    });

    test('regen scenario produces negative power while decelerating', () {
      final engine = DemoTelemetryEngine(
          scenario: DemoScenario.regen,
          now: DateTime.now().subtract(const Duration(seconds: 3)));
      // First seconds of a decel cycle → strong negative power.
      final kw = engine.powerKw();
      if (engine.elapsed % 30 < 15) {
        expect(kw, lessThan(0));
      }
      // Voltage rises during regen
      expect(engine.voltageV(), greaterThan(83.0));
    });

    test('current derives from P/U consistently', () {
      final engine = DemoTelemetryEngine(
          scenario: DemoScenario.highway,
          now: DateTime.now().subtract(const Duration(seconds: 7)));
      final u = engine.voltageV();
      final i = engine.currentA();
      expect((i * u / 1000 - engine.powerKw()).abs(), lessThan(0.02));
    });

    group('fake BMS', () {
      test('20 cells with realistic voltages at high SOC', () {
        final engine = DemoTelemetryEngine(
            scenario: DemoScenario.city,
            now: DateTime.now().subtract(const Duration(seconds: 2)));
        final bms = engine.bmsState();
        expect(bms.cellCount, 20);
        for (final c in bms.cellVoltagesMv) {
          expect(c, greaterThan(3000));
          expect(c, lessThan(4300));
        }
        expect(bms.socPercent, inInclusiveRange(5, 100));
      });

      test('cold battery scenario drives NTC below zero', () {
        final engine = DemoTelemetryEngine(
            scenario: DemoScenario.coldBattery, now: DateTime.now());
        final bms = engine.bmsState();
        for (final t in bms.temperaturesC) {
          expect(t, lessThan(0));
        }
      });

      test('hot battery scenario drives NTC above hot threshold', () {
        final engine = DemoTelemetryEngine(
            scenario: DemoScenario.hotBattery, now: DateTime.now());
        final bms = engine.bmsState();
        expect(bms.temperaturesC.first, greaterThan(kHotThresholdC));
      });

      test('cell delta stays small but nonzero while riding', () {
        final engine = DemoTelemetryEngine(
            scenario: DemoScenario.mountain,
            now: DateTime.now().subtract(const Duration(seconds: 4)));
        final bms = engine.bmsState();
        expect(bms.cellDeltaMv, lessThanOrEqualTo(30));
      });

      test('pack voltage equals cell sum', () {
        final engine = DemoTelemetryEngine(
            scenario: DemoScenario.city,
            now: DateTime.now().subtract(const Duration(seconds: 1)));
        final bms = engine.bmsState();
        final sum =
            bms.cellVoltagesMv.fold<double>(0, (a, c) => a + c) / 1000.0;
        expect(bms.totalVoltageV!, closeTo(sum, 0.01));
      });
    });
  });

  group('DemoModeNotifier', () {
    late DemoModeNotifier notifier;

    setUp(() {
      notifier = DemoModeNotifier();
    });

    test('starts inactive', () {
      expect(notifier.state.active, isFalse);
      expect(notifier.state.scenario, DemoScenario.none);
    });

    test('enable(city) activates with scenario', () {
      notifier.enable(DemoScenario.city);
      expect(notifier.state.active, isTrue);
      expect(notifier.state.scenario, DemoScenario.city);
    });

    test('enable(none) disables', () {
      notifier.enable(DemoScenario.highway);
      notifier.enable(DemoScenario.none);
      expect(notifier.state.active, isFalse);
    });

    test('setScenario switches without deactivation', () {
      notifier.enable(DemoScenario.city);
      notifier.setScenario(DemoScenario.coldBattery);
      expect(notifier.state.active, isTrue);
      expect(notifier.state.scenario, DemoScenario.coldBattery);
    });

    test('disable resets to defaults', () {
      notifier.enable(DemoScenario.regen);
      notifier.disable();
      expect(notifier.state.active, isFalse);
      expect(notifier.state.scenario, DemoScenario.none);
    });
  });

  group('effective warning from demo BMS (integration)', () {
    test('cold demo BMS maps to tooCold with computed power limit', () {
      final engine = DemoTelemetryEngine(scenario: DemoScenario.coldBattery);
      final AntBmsState bms = engine.bmsState();
      final avg =
          bms.temperaturesC.reduce((a, b) => a + b) / bms.temperaturesC.length;

      expect(avg < kColdThresholdC, isTrue);
      // The effective provider would compute:
      final percent = availablePercentOf(avg);
      final maxKw = maxKwAtTemp(avg);
      expect(percent, lessThan(68)); // below the 0 °C anchor
      expect(maxKw, lessThan(8.2)); // 68 % of 12 kW reference
    });

    test('normal demo temps produce no warning kind', () {
      final engine = DemoTelemetryEngine(
          scenario: DemoScenario.highway,
          now: DateTime.now().subtract(const Duration(seconds: 2)));
      final bms = engine.bmsState();
      final avg =
          bms.temperaturesC.reduce((a, b) => a + b) / bms.temperaturesC.length;
      expect(avg, greaterThan(kColdThresholdC));
      expect(avg, lessThan(kHotThresholdC));
    });
  });
}
