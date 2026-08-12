import 'package:arcdash/models/controller_identity.dart';

enum ParameterRisk {
  comfort,
  performance,
  safetyCritical,
  hardware,
}

enum ParameterCategory {
  motor,
  speedRatios,
  gearRatios,
  regen,
  pins,
  display,
  protect,
  pid,
  flags,
  calibration,
}

class ParameterDefinition {
  final String name;
  final int address;
  final int? minRaw;
  final int? maxRaw;
  final int mask;
  final int shift;
  final ParameterRisk risk;
  final ParameterCategory category;
  final bool readable;
  final bool hardwareBoundsConfirmed;

  /// SI-unit bounds of the parameter (e.g. km/h, A, V, °C, s, %). Used by the
  /// validator to reject values outside the hardware envelope before any conversion.
  final double? minPhysical;
  final double? maxPhysical;
  final String unit;
  final String description;

  const ParameterDefinition({
    required this.name,
    required this.address,
    required this.minRaw,
    required this.maxRaw,
    this.mask = 0xFFFF,
    this.shift = 0,
    required this.risk,
    this.category = ParameterCategory.motor,
    required this.readable,
    required this.hardwareBoundsConfirmed,
    this.minPhysical,
    this.maxPhysical,
    this.unit = '',
    this.description = '',
  });

  bool get writable =>
      readable && hardwareBoundsConfirmed && minRaw != null && maxRaw != null;

  bool inPhysicalRange(num value) =>
      minPhysical != null &&
      maxPhysical != null &&
      value.toDouble() >= minPhysical! &&
      value.toDouble() <= maxPhysical!;

  int? validateRaw(int value) {
    if (!writable || value < minRaw! || value > maxRaw!) return null;
    return value;
  }

  int applyToWord(int currentWord, int value) {
    final checked = validateRaw(value);
    if (checked == null) {
      throw StateError(
          '$name has no confirmed writable bounds or out of range: $value');
    }
    return (currentWord & ~mask) | ((checked << shift) & mask);
  }
}

class ParameterCatalog {
  static const definitions = <String, ParameterDefinition>{
    // -------------------------------------------------------------------------
    // 1. Motor & Basic Parameters
    // -------------------------------------------------------------------------
    'maxSpeed': ParameterDefinition(
      name: 'maxSpeed',
      address: 0x15,
      minRaw: 720, // 10 km/h
      maxRaw: 11520, // 160 km/h (9000 RPM raw ~ 125 km/h)
      risk: ParameterRisk.safetyCritical,
      category: ParameterCategory.motor,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 10,
      maxPhysical: 160,
      unit: 'km/h',
      description: 'Maximale Fahrzeug-Höchstgeschwindigkeit',
    ),
    'maxLineCurrent': ParameterDefinition(
      name: 'maxLineCurrent',
      address: 0x19,
      minRaw: 40, // 10 A * 4
      maxRaw: 1200, // 300 A * 4
      risk: ParameterRisk.safetyCritical,
      category: ParameterCategory.motor,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 10,
      maxPhysical: 300,
      unit: 'A',
      description: 'Maximaler Batteriestrom (Line Current)',
    ),
    'maxPhaseCurrent': ParameterDefinition(
      name: 'maxPhaseCurrent',
      address: 0x1B, // 0x2A block, 4th word -> 0x2D in some maps or 0x1B
      minRaw: 80, // 20 A * 4
      maxRaw: 2200, // 550 A * 4
      risk: ParameterRisk.safetyCritical,
      category: ParameterCategory.motor,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 20,
      maxPhysical: 550,
      unit: 'A',
      description: 'Maximaler Phasenstrom (Peak Torque)',
    ),
    'throttleResponse': ParameterDefinition(
      name: 'throttleResponse',
      address: 0x1A,
      minRaw: 0,
      maxRaw: 3,
      mask: 0x000C,
      shift: 2,
      risk: ParameterRisk.comfort,
      category: ParameterCategory.motor,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0,
      maxPhysical: 3,
      unit: 'mode',
      description: 'Gasannahme-Kurve (0=Line/Race, 1=Sport, 2=ECO)',
    ),
    'ratedSpeed': ParameterDefinition(
      name: 'ratedSpeed',
      address: 0x18,
      minRaw: 1000,
      maxRaw: 12000,
      risk: ParameterRisk.hardware,
      category: ParameterCategory.motor,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 1000,
      maxPhysical: 12000,
      unit: 'RPM',
      description: 'Motornenndrehzahl',
    ),
    'ratedVoltage': ParameterDefinition(
      name: 'ratedVoltage',
      address: 0x17,
      minRaw: 240, // 24 V * 10
      maxRaw: 1200, // 120 V * 10
      risk: ParameterRisk.hardware,
      category: ParameterCategory.motor,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 24,
      maxPhysical: 120,
      unit: 'V',
      description: 'Nennspannung des Antriebsstrangs',
    ),
    'ratedPower': ParameterDefinition(
      name: 'ratedPower',
      address: 0x16,
      minRaw: 500,
      maxRaw: 30000,
      risk: ParameterRisk.hardware,
      category: ParameterCategory.motor,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 500,
      maxPhysical: 30000,
      unit: 'W',
      description: 'Nennleistung des Motors',
    ),
    'polePairs': ParameterDefinition(
      name: 'polePairs',
      address: 0x14,
      minRaw: 1,
      maxRaw: 32,
      mask: 0x00FF,
      shift: 0,
      risk: ParameterRisk.hardware,
      category: ParameterCategory.motor,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 1,
      maxPhysical: 32,
      unit: 'pairs',
      description: 'Anzahl der Motorpolpaare',
    ),
    'phaseOffset': ParameterDefinition(
      name: 'phaseOffset',
      address: 0x0C,
      minRaw: 0,
      maxRaw: 3600,
      risk: ParameterRisk.hardware,
      category: ParameterCategory.motor,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0,
      maxPhysical: 360,
      unit: '°',
      description: 'Elektrischer Phasenversatzwinkel',
    ),
    'tempSensor': ParameterDefinition(
      name: 'tempSensor',
      address: 0x11, // in block 0x06 (word 5 -> 0x0B)
      minRaw: 0,
      maxRaw: 7,
      mask: 0x0070,
      shift: 4,
      risk: ParameterRisk.hardware,
      category: ParameterCategory.motor,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0,
      maxPhysical: 7,
      unit: 'type',
      description: 'Motortemperatursensor-Typ (z.B. NTC10K, KTY84)',
    ),
    'motorDirection': ParameterDefinition(
      name: 'motorDirection',
      address: 0x0B,
      minRaw: 0,
      maxRaw: 1,
      mask: 0x8000,
      shift: 15,
      risk: ParameterRisk.hardware,
      category: ParameterCategory.motor,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0,
      maxPhysical: 1,
      unit: 'dir',
      description: 'Drehrichtung des Motors (0=Standard, 1=Invertiert)',
    ),
    'backSpeed': ParameterDefinition(
      name: 'backSpeed',
      address: 0x28,
      minRaw: 100,
      maxRaw: 4000,
      risk: ParameterRisk.comfort,
      category: ParameterCategory.motor,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 100,
      maxPhysical: 4000,
      unit: 'RPM',
      description: 'Maximale Rückwärtsfahr-Drehzahl',
    ),
    'boostLineCurr': ParameterDefinition(
      name: 'boostLineCurr',
      address: 0x26,
      minRaw: 40,
      maxRaw: 1400,
      risk: ParameterRisk.performance,
      category: ParameterCategory.motor,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 10,
      maxPhysical: 350,
      unit: 'A',
      description: 'Temporärer Maximaler Batteriestrom im Boost-Modus',
    ),
    'boostPhaseCurr': ParameterDefinition(
      name: 'boostPhaseCurr',
      address: 0x27,
      minRaw: 80,
      maxRaw: 2600,
      risk: ParameterRisk.performance,
      category: ParameterCategory.motor,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 20,
      maxPhysical: 650,
      unit: 'A',
      description: 'Temporärer Maximaler Phasenstrom im Boost-Modus',
    ),
    'throttleLow': ParameterDefinition(
      name: 'throttleLow',
      address: 0x08,
      minRaw: 5,
      maxRaw: 50,
      mask: 0x00FF,
      shift: 0,
      risk: ParameterRisk.safetyCritical,
      category: ParameterCategory.motor,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0.25,
      maxPhysical: 2.5,
      unit: 'V',
      description: 'Gasgriff-Ruhespannung (Start-Schwelle)',
    ),
    'throttleHigh': ParameterDefinition(
      name: 'throttleHigh',
      address: 0x08,
      minRaw: 50,
      maxRaw: 100,
      mask: 0xFF00,
      shift: 8,
      risk: ParameterRisk.safetyCritical,
      category: ParameterCategory.motor,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 2.5,
      maxPhysical: 5.0,
      unit: 'V',
      description: 'Gasgriff-Vollgas-Endspannung',
    ),
    'throttleAccStep': ParameterDefinition(
      name: 'throttleAccStep',
      address: 0x2F,
      minRaw: 10,
      maxRaw: 500,
      risk: ParameterRisk.comfort,
      category: ParameterCategory.motor,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 10,
      maxPhysical: 500,
      unit: 'step',
      description: 'Gasannahme-Anstiegsgeschwindigkeit (Ramp-Up)',
    ),
    'throttleDecStep': ParameterDefinition(
      name: 'throttleDecStep',
      address: 0x2B,
      minRaw: 10,
      maxRaw: 500,
      risk: ParameterRisk.comfort,
      category: ParameterCategory.motor,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 10,
      maxPhysical: 500,
      unit: 'step',
      description: 'Gaswegnahme-Abfallgeschwindigkeit (Ramp-Down)',
    ),

    // -------------------------------------------------------------------------
    // 2. Ratios in Gear (Modus 1 & Modus 2)
    // -------------------------------------------------------------------------
    'lowSpeedLineCurr': ParameterDefinition(
      name: 'lowSpeedLineCurr',
      address: 0x32,
      minRaw: 10,
      maxRaw: 128,
      mask: 0x00FF,
      shift: 0,
      risk: ParameterRisk.comfort,
      category: ParameterCategory.gearRatios,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 10,
      maxPhysical: 100,
      unit: '%',
      description: 'Strombegrenzung in Modus 1 (LOW / DL)',
    ),
    'midSpeedLineCurr': ParameterDefinition(
      name: 'midSpeedLineCurr',
      address: 0x32,
      minRaw: 10,
      maxRaw: 128,
      mask: 0xFF00,
      shift: 8,
      risk: ParameterRisk.comfort,
      category: ParameterCategory.gearRatios,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 10,
      maxPhysical: 100,
      unit: '%',
      description: 'Strombegrenzung in Modus 2 (MEDIUM / DM)',
    ),
    'lowSpeedPhaseCurr': ParameterDefinition(
      name: 'lowSpeedPhaseCurr',
      address: 0x33,
      minRaw: 10,
      maxRaw: 128,
      mask: 0x00FF,
      shift: 0,
      risk: ParameterRisk.comfort,
      category: ParameterCategory.gearRatios,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 10,
      maxPhysical: 100,
      unit: '%',
      description: 'Drehmomentbegrenzung in Modus 1 (LOW / DL)',
    ),
    'midSpeedPhaseCurr': ParameterDefinition(
      name: 'midSpeedPhaseCurr',
      address: 0x33,
      minRaw: 10,
      maxRaw: 128,
      mask: 0xFF00,
      shift: 8,
      risk: ParameterRisk.comfort,
      category: ParameterCategory.gearRatios,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 10,
      maxPhysical: 100,
      unit: '%',
      description: 'Drehmomentbegrenzung in Modus 2 (MEDIUM / DM)',
    ),

    // -------------------------------------------------------------------------
    // 3. Energy Regeneration & Braking
    // -------------------------------------------------------------------------
    'stopBackCurr': ParameterDefinition(
      name: 'stopBackCurr',
      address: 0x30,
      minRaw: 0,
      maxRaw: 100,
      risk: ParameterRisk.performance,
      category: ParameterCategory.regen,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0,
      maxPhysical: 100,
      unit: 'A',
      description: 'Rekuperationsstrom bei Stillstand / niedriger Drehzahl',
    ),
    'maxBackCurr': ParameterDefinition(
      name: 'maxBackCurr',
      address: 0x31,
      minRaw: 0,
      maxRaw: 150,
      risk: ParameterRisk.performance,
      category: ParameterCategory.regen,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0,
      maxPhysical: 150,
      unit: 'A',
      description: 'Maximaler Rekuperationsstrom beim Bremsen',
    ),
    'freeThrottle': ParameterDefinition(
      name: 'freeThrottle',
      address: 0x2C,
      minRaw: 0,
      maxRaw: 100,
      mask: 0x00FF,
      shift: 0,
      risk: ParameterRisk.comfort,
      category: ParameterCategory.regen,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0,
      maxPhysical: 100,
      unit: '%',
      description: 'Motorbremswirkung bei losgelassenem Gasgriff',
    ),
    'brakeVoltage': ParameterDefinition(
      name: 'brakeVoltage',
      address: 0x82,
      minRaw: 0,
      maxRaw: 500,
      risk: ParameterRisk.safetyCritical,
      category: ParameterCategory.regen,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0,
      maxPhysical: 5.0,
      unit: 'V',
      description: 'Spannungsschwelle für variablen Bremsgriff',
    ),

    // -------------------------------------------------------------------------
    // 4. Protection & Cutoffs
    // -------------------------------------------------------------------------
    'lowVoltCutoff': ParameterDefinition(
      name: 'lowVoltCutoff',
      address: 0x1F,
      minRaw: 400, // 40V * 10
      maxRaw: 900, // 90V * 10
      risk: ParameterRisk.safetyCritical,
      category: ParameterCategory.protect,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 40,
      maxPhysical: 90,
      unit: 'V',
      description: 'Batterie-Unterspannungsabschaltung (LVC)',
    ),
    'overVoltCutoff': ParameterDefinition(
      name: 'overVoltCutoff',
      address: 0x25,
      minRaw: 700, // 70V * 10
      maxRaw: 1100, // 110V * 10
      risk: ParameterRisk.safetyCritical,
      category: ParameterCategory.protect,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 70,
      maxPhysical: 110,
      unit: 'V',
      description: 'Batterie-Überspannungsschutz (OVP)',
    ),
    'motorTempLimit': ParameterDefinition(
      name: 'motorTempLimit',
      address: 0x84,
      minRaw: 70,
      maxRaw: 160,
      mask: 0x00FF,
      shift: 0,
      risk: ParameterRisk.safetyCritical,
      category: ParameterCategory.protect,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 70,
      maxPhysical: 160,
      unit: '°C',
      description: 'Motortemperatur-Schutzgrenze',
    ),
    'controllerTempLimit': ParameterDefinition(
      name: 'controllerTempLimit',
      address: 0x85,
      minRaw: 60,
      maxRaw: 120,
      mask: 0x00FF,
      shift: 0,
      risk: ParameterRisk.safetyCritical,
      category: ParameterCategory.protect,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 60,
      maxPhysical: 120,
      unit: '°C',
      description: 'Controller-/MOSFET-Temperaturschutzgrenze',
    ),
    'boostTime': ParameterDefinition(
      name: 'boostTime',
      address: 0xC0, // in AddrBE block
      minRaw: 0,
      maxRaw: 30000, // 60s * 500
      risk: ParameterRisk.performance,
      category: ParameterCategory.protect,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0,
      maxPhysical: 60,
      unit: 's',
      description: 'Maximale Dauer des Boost-Modus',
    ),
    'fluxWeakeningCurr': ParameterDefinition(
      name: 'fluxWeakeningCurr',
      address: 0x12, // LD in block 0x12
      minRaw: 0,
      maxRaw: 2000,
      risk: ParameterRisk.performance,
      category: ParameterCategory.pid,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0,
      maxPhysical: 2000,
      unit: 'raw',
      description: 'Feldschwächungs-Koeffizient (LD)',
    ),

    // -------------------------------------------------------------------------
    // 5. PID & Feldschwächung
    // -------------------------------------------------------------------------
    'anWaveType': ParameterDefinition(
      name: 'anWaveType',
      address: 0x9C,
      minRaw: 0,
      maxRaw: 15,
      mask: 0x000F,
      shift: 0,
      risk: ParameterRisk.performance,
      category: ParameterCategory.pid,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0,
      maxPhysical: 15,
      unit: 'type',
      description: 'Vibrationsunterdrückung & Wellentyp (AN)',
    ),
    'lmWaveInterval': ParameterDefinition(
      name: 'lmWaveInterval',
      address: 0x9D,
      minRaw: 0,
      maxRaw: 31,
      mask: 0x001F,
      shift: 0,
      risk: ParameterRisk.performance,
      category: ParameterCategory.pid,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0,
      maxPhysical: 31,
      unit: 'interval',
      description: 'Feldschwächungs-Wellenintervall (LM)',
    ),
    'speedKI': ParameterDefinition(
      name: 'speedKI',
      address: 0x07,
      minRaw: 0,
      maxRaw: 255,
      mask: 0x00FF,
      shift: 0,
      risk: ParameterRisk.performance,
      category: ParameterCategory.pid,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0,
      maxPhysical: 255,
      unit: 'gain',
      description: 'Drehzahlregler Integralverstärkung (SpeedKI)',
    ),
    'speedKP': ParameterDefinition(
      name: 'speedKP',
      address: 0x07,
      minRaw: 0,
      maxRaw: 255,
      mask: 0xFF00,
      shift: 8,
      risk: ParameterRisk.performance,
      category: ParameterCategory.pid,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0,
      maxPhysical: 255,
      unit: 'gain',
      description: 'Drehzahlregler Proportionalverstärkung (SpeedKP)',
    ),

    // -------------------------------------------------------------------------
    // 6. Display & CAN & Tacho
    // -------------------------------------------------------------------------
    'wheelRadius': ParameterDefinition(
      name: 'wheelRadius',
      address: 0xD2,
      minRaw: 8,
      maxRaw: 26,
      mask: 0xFF00,
      shift: 8,
      risk: ParameterRisk.comfort,
      category: ParameterCategory.display,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 8,
      maxPhysical: 26,
      unit: 'inch',
      description: 'Felgenradius für Tacho-Berechnung',
    ),
    'wheelWidth': ParameterDefinition(
      name: 'wheelWidth',
      address: 0xD3,
      minRaw: 40,
      maxRaw: 300,
      mask: 0xFF00,
      shift: 8,
      risk: ParameterRisk.comfort,
      category: ParameterCategory.display,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 40,
      maxPhysical: 300,
      unit: 'mm',
      description: 'Reifenbreite in Millimeter',
    ),
    'wheelRatio': ParameterDefinition(
      name: 'wheelRatio',
      address: 0xD2,
      minRaw: 30,
      maxRaw: 150,
      mask: 0x00FF,
      shift: 0,
      risk: ParameterRisk.comfort,
      category: ParameterCategory.display,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 30,
      maxPhysical: 150,
      unit: '%',
      description: 'Reifenquerschnitts-Verhältnis',
    ),
    'canBaud': ParameterDefinition(
      name: 'canBaud',
      address: 0xBD,
      minRaw: 0,
      maxRaw: 2,
      mask: 0x0300,
      shift: 8,
      risk: ParameterRisk.hardware,
      category: ParameterCategory.display,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0,
      maxPhysical: 2,
      unit: 'baud',
      description: 'CAN-Bus Baudrate (0=250k, 1=500k, 2=1M)',
    ),
  };

  const ParameterCatalog();

  ParameterDefinition operator [](String name) {
    final definition = definitions[name];
    if (definition == null) throw ArgumentError.value(name, 'name');
    return definition;
  }

  List<ParameterDefinition> get byCategory => definitions.values.toList();

  List<ParameterDefinition> forCategory(ParameterCategory category) =>
      definitions.values.where((d) => d.category == category).toList();
}

enum SafetyRejection {
  disconnected,
  unknownIdentity,
  staleTelemetry,
  insufficientSamples,
  moving,
  motorRunning,
  faultActive,
  directionUnknown,
  brakeActive,
  throttleNotZero,
  missingBackup,
}

/// Human-readable description of the rejections that block a write. Used by
/// the tuning UI and the audit log.
String describeSafety(SafetyDecision decision) {
  if (decision.allowed) return 'Schreibvorgang autorisiert';
  final reasons = <String>{
    for (final rejection in decision.rejections)
      switch (rejection) {
        SafetyRejection.disconnected => 'Controller nicht verbunden',
        SafetyRejection.unknownIdentity => 'Controller-Identität unbestätigt',
        SafetyRejection.staleTelemetry => 'Telemetriedaten veraltet',
        SafetyRejection.insufficientSamples => 'Zu wenige Stillstands-Samples',
        SafetyRejection.moving => 'Fahrzeug in Bewegung (> 0 km/h)',
        SafetyRejection.motorRunning => 'Motor läuft noch',
        SafetyRejection.faultActive => 'Aktiver Controller-Fehler',
        SafetyRejection.directionUnknown => 'Fahrtrichtung unklar',
        SafetyRejection.brakeActive => 'Bremse betätigt',
        SafetyRejection.throttleNotZero => 'Gasgriff nicht auf Null',
        SafetyRejection.missingBackup => 'Kein verifiziertes Backup vorhanden',
      },
  };
  return reasons.join(', ');
}

class SafetySample {
  final DateTime at;
  final int rpm;
  final double speedKph;
  final bool motorRunning;
  final bool directionKnown;
  final bool brakeActive;
  final bool throttleZero;
  final bool faultActive;

  const SafetySample({
    required this.at,
    required this.rpm,
    this.speedKph = 0.0,
    required this.motorRunning,
    required this.directionKnown,
    required this.brakeActive,
    required this.throttleZero,
    this.faultActive = false,
  });
}

class SafetyDecision {
  final bool allowed;
  final Set<SafetyRejection> rejections;

  const SafetyDecision({required this.allowed, required this.rejections});
}

/// Fail-closed safety evaluator. A write is only allowed when every checked
/// condition holds; the first violated condition yields a typed rejection.
class SafetyEvaluator {
  final Duration maxTelemetryAge;
  final int requiredSamples;

  const SafetyEvaluator({
    this.maxTelemetryAge = const Duration(milliseconds: 1500),
    this.requiredSamples = 3,
  });

  SafetyDecision evaluate({
    required DateTime now,
    required bool connected,
    required ControllerIdentity identity,
    required bool backupAvailable,
    required List<SafetySample> samples,
  }) {
    final rejections = <SafetyRejection>{};
    if (!connected) rejections.add(SafetyRejection.disconnected);
    if (!identity.isComplete) rejections.add(SafetyRejection.unknownIdentity);
    if (!backupAvailable) rejections.add(SafetyRejection.missingBackup);
    if (samples.length < requiredSamples) {
      rejections.add(SafetyRejection.insufficientSamples);
    }
    if (samples.isEmpty || now.difference(samples.last.at) > maxTelemetryAge) {
      rejections.add(SafetyRejection.staleTelemetry);
    }
    for (final sample in samples) {
      if (sample.rpm != 0 || sample.speedKph != 0.0) {
        rejections.add(SafetyRejection.moving);
      }
      if (sample.motorRunning) rejections.add(SafetyRejection.motorRunning);
      if (!sample.directionKnown) {
        rejections.add(SafetyRejection.directionUnknown);
      }
      if (sample.brakeActive) rejections.add(SafetyRejection.brakeActive);
      if (!sample.throttleZero) rejections.add(SafetyRejection.throttleNotZero);
      if (sample.faultActive) rejections.add(SafetyRejection.faultActive);
    }
    return SafetyDecision(
      allowed: rejections.isEmpty,
      rejections: Set.unmodifiable(rejections),
    );
  }

  /// Evaluates a single live telemetry snapshot against the immutable
  /// write-conditions: connected, standing still, fresh stream, no faults.
  SafetyDecision evaluateState({
    required DateTime now,
    required bool connected,
    required ControllerIdentity identity,
    required bool backupAvailable,
    required double speedKph,
    required DateTime lastUpdate,
    required bool hasFault,
  }) {
    final rejections = <SafetyRejection>{};
    if (!connected) rejections.add(SafetyRejection.disconnected);
    if (!identity.isComplete) rejections.add(SafetyRejection.unknownIdentity);
    if (!backupAvailable) rejections.add(SafetyRejection.missingBackup);
    if (speedKph != 0.0) rejections.add(SafetyRejection.moving);
    if (now.difference(lastUpdate) > maxTelemetryAge) {
      rejections.add(SafetyRejection.staleTelemetry);
    }
    if (hasFault) rejections.add(SafetyRejection.faultActive);
    return SafetyDecision(
      allowed: rejections.isEmpty,
      rejections: Set.unmodifiable(rejections),
    );
  }
}
