import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/utils/battery_soc_calculator.dart';
import 'package:arcdash/models/range_prediction_state.dart';

void main() {
  group('BatterySocCalculator 20S Li-Ion Tests', () {
    test('Calculates 100% at full voltage 84.0V and 0% at cutoff 62.0V', () {
      final soc100 = BatterySocCalculator.calculateSoc(ocvVoltageV: 84.0);
      expect(soc100, 100.0);

      final socOver = BatterySocCalculator.calculateSoc(ocvVoltageV: 85.0);
      expect(socOver, 100.0);

      final soc0 = BatterySocCalculator.calculateSoc(ocvVoltageV: 62.0);
      expect(soc0, 0.0);

      final socUnder = BatterySocCalculator.calculateSoc(ocvVoltageV: 59.0);
      expect(socUnder, 0.0);
    });

    test('Interpolates accurately along 20S OCV curve', () {
      final soc78 = BatterySocCalculator.calculateSoc(ocvVoltageV: 78.0);
      expect(soc78, closeTo(70.0, 0.5));

      final soc75 = BatterySocCalculator.calculateSoc(ocvVoltageV: 75.0);
      expect(soc75, closeTo(50.0, 0.5));

      final soc80 = BatterySocCalculator.calculateSoc(ocvVoltageV: 80.0);
      expect(soc80, closeTo(80.0, 0.5));
    });

    test('Compensates load-sag using pack internal resistance', () {
      // Resting battery at 78.0V (70% SOC)
      final restingOcv = BatterySocCalculator.estimateOcv(
        terminalVoltageV: 78.0,
        currentA: 0.0,
      );
      expect(restingOcv, 78.0);
      expect(BatterySocCalculator.calculateSoc(ocvVoltageV: restingOcv),
          closeTo(70.0, 0.5));

      // Accelerating hard: 100A current causes 3.5V sag -> terminal drops to 74.5V
      final saggedOcv = BatterySocCalculator.estimateOcv(
        terminalVoltageV: 74.5,
        currentA: 100.0,
        packResistanceOhm: 0.035,
      );
      // Compensated OCV should be 74.5 + 3.5 = 78.0V!
      expect(saggedOcv, closeTo(78.0, 0.1));
      expect(BatterySocCalculator.calculateSoc(ocvVoltageV: saggedOcv),
          closeTo(70.0, 0.5));
    });

    test(
        'Rejects collapsed calibration window (< 15V span) and falls back to 20S defaults',
        () {
      // Corrupted calibration in database had 83.0V min and 83.6V max (0.6V span)
      final socWithCorruptedBounds = BatterySocCalculator.calculateSoc(
        ocvVoltageV: 78.0,
        minVoltageV: 83.0,
        maxVoltageV: 83.6,
      );

      // Must not collapse to 0% or 100%! Must use 62V..84V fallback -> ~70%
      expect(socWithCorruptedBounds, closeTo(70.0, 1.0));
    });

    test('RangePredictionState.sanitized() resets narrow spans to defaults',
        () {
      const corrupted = RangePredictionState(
        controllerId: 'FD-CORRUPT',
        minVoltageV: 83.0,
        maxVoltageV: 83.6,
      );
      expect(corrupted.hasValidCalibration, isFalse);

      final clean = corrupted.sanitized();
      expect(clean.minVoltageV, 62.0);
      expect(clean.maxVoltageV, 84.0);
      expect(clean.hasValidCalibration, isTrue);
    });
  });
}
