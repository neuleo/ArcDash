/// Fine-grained battery temperature → available power mapping.
///
/// Research basis (2026-08, see plan/15-temperatur-management.md):
/// - Battery University BU-502: at –20 °C most batteries deliver ~50 % of
///   their rated performance; Li-ion discharge range is –20 °C…60 °C.
/// - Battery University BU-410: charging (incl. regen braking!) below 0 °C
///   causes lithium plating → permanent cell damage.
/// - Wikipedia / literature: >30 °C accelerates aging (–20 % cycle life),
///   >40 °C –40 % cycle life; power derating above 45 °C is standard BMS
///   practice for NMC packs.
///
/// The anchor tables below are interpolated LINEARLY between points with
/// 0.1 °C resolution — no coarse steps.
library;

enum BatteryChemistry { nmc, lfp }

class _Anchor {
  final double tempC;
  final double percent;
  const _Anchor(this.tempC, this.percent);
}

/// NMC anchors (Arctic Leopard XE Pro default chemistry, 20S pack,
/// full charge ≈ 4.19 V/cell).
const List<_Anchor> _nmcAnchors = [
  _Anchor(-30, 0), // below discharge range: no high load allowed
  _Anchor(-25, 8),
  _Anchor(-20, 25), // BU-502: ~50 % performance, we derate harder for power
  _Anchor(-15, 32),
  _Anchor(-10, 42),
  _Anchor(-5, 55),
  _Anchor(0, 68),
  _Anchor(5, 80),
  _Anchor(10, 90),
  _Anchor(15, 96),
  _Anchor(20, 100),
  _Anchor(25, 100),
  _Anchor(30, 98),
  _Anchor(35, 96),
  _Anchor(40, 92),
  _Anchor(45, 85),
  _Anchor(50, 75),
  _Anchor(55, 60),
  _Anchor(60, 45),
  _Anchor(65, 0), // thermal shutdown region
];

/// LFP anchors (optional selectable chemistry profile).
const List<_Anchor> _lfpAnchors = [
  _Anchor(-30, 0),
  _Anchor(-20, 20),
  _Anchor(-10, 38),
  _Anchor(0, 62),
  _Anchor(10, 85),
  _Anchor(20, 100),
  _Anchor(30, 100),
  _Anchor(45, 95),
  _Anchor(55, 80),
  _Anchor(60, 70),
  _Anchor(70, 0),
];

List<_Anchor> _anchorsFor(BatteryChemistry chem) =>
    chem == BatteryChemistry.lfp ? _lfpAnchors : _nmcAnchors;

/// Available power as percent (0..100) of the rated max at [tempC].
///
/// Interpolates linearly between neighbouring anchors. Temperatures are
/// clamped to the table range (below/above → 0 %).
double availablePercent(double tempC,
    {BatteryChemistry chem = BatteryChemistry.nmc}) {
  final anchors = _anchorsFor(chem);
  if (tempC <= anchors.first.tempC || tempC >= anchors.last.tempC) {
    return 0;
  }
  for (var i = 0; i < anchors.length - 1; i++) {
    final a = anchors[i];
    final b = anchors[i + 1];
    if (tempC >= a.tempC && tempC <= b.tempC) {
      final t = (tempC - a.tempC) / (b.tempC - a.tempC);
      return a.percent + t * (b.percent - a.percent);
    }
  }
  return 0; // unreachable
}

/// Allowed maximum power in kW at [tempC] for a pack rated at
/// [ratedMaxKw] kW (100 %).
double maxPowerKwAt(
  double tempC, {
  double ratedMaxKw = 12.0,
  BatteryChemistry chem = BatteryChemistry.nmc,
}) =>
    maxPowerKwFromPercent(ratedMaxKw, availablePercent(tempC, chem: chem));

/// Convenience: derive kW from an already computed percent.
double maxPowerKwFromPercent(double ratedMaxKw, double percent) =>
    ((ratedMaxKw * percent) / 100).clamp(0.0, ratedMaxKw);

/// True when regenerative braking should be blocked/warned because the pack
/// is cold enough to risk lithium plating (< 0 °C). Source: BU-410.
bool isRegenRisky(double tempC) => tempC < 0.0;
