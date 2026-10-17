import 'dart:math' as math;

/// Calculates battery state of charge (SOC) for 20S Li-Ion setups (nominal 72V, max 84V)
/// with internal resistance / load-sag compensation and non-linear OCV mapping.
class BatterySocCalculator {
  static const double defaultMinVoltageV = 62.0;
  static const double defaultMaxVoltageV = 84.0;

  /// Standard 20S Li-Ion OCV table (Terminal OCV Voltage, SOC %).
  /// Arctic Leopard XE Pro S uses 20S NMC/INR chemistry (approx 3.10V cutoff to 4.20V full).
  static const List<(double, double)> ocvPoints20S = [
    (62.0, 0.0), // 3.10 V/cell - cutoff / 0%
    (65.0, 5.0), // 3.25 V/cell
    (68.4, 10.0), // 3.42 V/cell
    (70.4, 20.0), // 3.52 V/cell
    (72.0, 30.0), // 3.60 V/cell
    (73.6, 40.0), // 3.68 V/cell
    (75.0, 50.0), // 3.75 V/cell
    (76.4, 60.0), // 3.82 V/cell
    (78.0, 70.0), // 3.90 V/cell
    (80.0, 80.0), // 4.00 V/cell
    (81.6, 90.0), // 4.08 V/cell
    (83.0, 95.0), // 4.15 V/cell
    (84.0, 100.0), // 4.20 V/cell - full
  ];

  /// Typical internal resistance of a ~3.8 kWh 20S battery pack in Ohms (~35 mOhm).
  static const double defaultPackResistanceOhm = 0.035;

  /// Estimates the open-circuit voltage (OCV) by adding back the voltage drop
  /// caused by discharge current through the pack internal resistance.
  /// When braking/regen (current < 0), terminal voltage rises, so correction is negative.
  static double estimateOcv({
    required double terminalVoltageV,
    required double currentA,
    double packResistanceOhm = defaultPackResistanceOhm,
  }) {
    if (!terminalVoltageV.isFinite || terminalVoltageV <= 0) return 0.0;
    // Clamping sag correction between -4V and +7V prevents distortion during transient noise spikes
    final sagDrop = (currentA * packResistanceOhm).clamp(-4.0, 7.0);
    return (terminalVoltageV + sagDrop).clamp(55.0, 86.0);
  }

  /// Calculates the SOC percentage (0..100) using the 20S OCV curve.
  /// If custom [minVoltageV] and [maxVoltageV] are provided, they must span at least 15.0V;
  /// otherwise the physical 20S bounds (62.0V - 84.0V) are enforced.
  static double calculateSoc({
    required double ocvVoltageV,
    double minVoltageV = 62.0,
    double maxVoltageV = 84.0,
  }) {
    if (!ocvVoltageV.isFinite || ocvVoltageV <= 0) return 0.0;

    final span = maxVoltageV - minVoltageV;
    if (span < 15.0) {
      // Degraded/collapsed calibration span - enforce physical 20S limits
      minVoltageV = 62.0;
      maxVoltageV = 84.0;
    }

    if (ocvVoltageV <= minVoltageV) return 0.0;
    if (ocvVoltageV >= maxVoltageV) return 100.0;

    // Normalize to standard 62.0..84.0 reference if custom bounds differ
    double normV = ocvVoltageV;
    if ((minVoltageV - 62.0).abs() > 0.5 || (maxVoltageV - 84.0).abs() > 0.5) {
      final ratio = (ocvVoltageV - minVoltageV) / (maxVoltageV - minVoltageV);
      normV = 62.0 + ratio * (84.0 - 62.0);
    }

    if (normV <= ocvPoints20S.first.$1) return ocvPoints20S.first.$2;
    if (normV >= ocvPoints20S.last.$1) return ocvPoints20S.last.$2;

    for (int i = 1; i < ocvPoints20S.length; i++) {
      final (vLow, socLow) = ocvPoints20S[i - 1];
      final (vHigh, socHigh) = ocvPoints20S[i];
      if (normV <= vHigh) {
        final frac = (normV - vLow) / (vHigh - vLow);
        return (socLow + frac * (socHigh - socLow)).clamp(0.0, 100.0);
      }
    }
    return 0.0;
  }
}
