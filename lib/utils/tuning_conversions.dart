/// SI-unit ↔ FarDriver raw-value conversions for tunable parameters.
///
/// Factors are fixed by the hardware bounds confirmed from
/// `reference/basemaps/unmodified_basemap.json`: factory maxSpeed raw
/// 0x2328 = 9000 = 125 km/h → 72 raw/km/h; factory maxLineCurrent raw 720 =
/// 180 A → 4 raw per ampere. ThrottleResponse mode lives in bits 2-3 of
/// address 0x1A.
class TuningConversions {
  static const int maxSpeedRawPerKph = 72;
  static const int maxLineCurrRawPerAmp = 4;

  static int maxSpeedKphToRaw(double kph) =>
      (kph * maxSpeedRawPerKph).round().clamp(0, 0xFFFF);

  static double maxSpeedRawToKph(int raw) => raw / maxSpeedRawPerKph;

  static int maxLineCurrAToRaw(double amps) =>
      (amps * maxLineCurrRawPerAmp).round().clamp(0, 0xFFFF);

  static double maxLineCurrRawToA(int raw) => raw / maxLineCurrRawPerAmp;

  /// ThrottleResponse mode (0=Line/Race, 1=Sport, 2=Eco) occupies bits 2-3.
  static int throttleResponseToRaw(int mode) => (mode & 0x03) << 2;
}
