import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/utils/battery_temp_power.dart';

void main() {
  group('BatteryTempPower', () {
    group('availablePercent NMC anchors are exact', () {
      final cases = <double, double>{
        -20: 25,
        -15: 32,
        -10: 42,
        -5: 55,
        0: 68,
        5: 80,
        10: 90,
        15: 96,
        20: 100,
        25: 100,
        30: 98,
        35: 96,
        40: 92,
        45: 85,
        50: 75,
        55: 60,
        60: 45,
      };
      cases.forEach((temp, expected) {
        test('$temp °C -> $expected %', () {
          expect(availablePercent(temp), closeTo(expected, 0.001));
        });
      });
    });

    group('fine-grained interpolation between anchors', () {
      test('-7.3 °C interpolates between -10 (42) and -5 (55)', () {
        // t = (-7.3 + 10) / 5 = 0.54 → 42 + 0.54 * 13 = 49.02
        expect(availablePercent(-7.3), closeTo(49.02, 0.01));
      });

      test('12.5 °C interpolates between 10 (90) and 15 (96)', () {
        expect(availablePercent(12.5), closeTo(93.0, 0.001));
      });

      test('47 °C interpolates between 45 (85) and 50 (75)', () {
        // t = 2/5 = 0.4 → 85 - 4 = 81
        expect(availablePercent(47), closeTo(81.0, 0.001));
      });

      test('sub-degree steps differ monotonically', () {
        final cold = availablePercent(-9.9);
        final warmer = availablePercent(-9.8);
        expect(warmer, greaterThan(cold));
        expect(warmer - cold, closeTo((42 - 55) / -5 * 0.1, 0.001));
      });
    });

    test('clamps below range and above range to 0 %', () {
      expect(availablePercent(-30.1), 0);
      expect(availablePercent(-31), 0);
      expect(availablePercent(65.1), 0);
      expect(availablePercent(80), 0);
    });

    test('LFP profile differs from NMC at same temps', () {
      expect(
        availablePercent(-10, chem: BatteryChemistry.lfp),
        closeTo(38, 0.001),
      );
      expect(
        availablePercent(0, chem: BatteryChemistry.lfp),
        closeTo(62, 0.001),
      );
      // NMC is hotter-derated earlier than LFP
      expect(availablePercent(50),
          lessThan(availablePercent(50, chem: BatteryChemistry.lfp)));
    });

    group('maxPowerKwAt multiplies rated max', () {
      test('12 kW pack at 0 °C (68 %) = 8.16 kW', () {
        expect(maxPowerKwAt(0, ratedMaxKw: 12.0), closeTo(8.16, 0.001));
      });

      test('12 kW pack at 20 °C (100 %) = 12 kW', () {
        expect(maxPowerKwAt(20, ratedMaxKw: 12.0), closeTo(12.0, 0.001));
      });

      test('never exceeds rated max even in warm sweet spot', () {
        expect(maxPowerKwAt(22, ratedMaxKw: 10.0), lessThanOrEqualTo(10.0));
      });

      test('freezing cold clamps to 0 kW', () {
        expect(maxPowerKwAt(-35, ratedMaxKw: 12.0), 0);
      });
    });

    group('isRegenRisky (lithium plating guard, BU-410)', () {
      test('below 0 °C risky', () {
        expect(isRegenRisky(-0.5), isTrue);
        expect(isRegenRisky(-10), isTrue);
      });

      test('at or above 0 °C safe', () {
        expect(isRegenRisky(0), isFalse);
        expect(isRegenRisky(15), isFalse);
      });
    });
  });
}
