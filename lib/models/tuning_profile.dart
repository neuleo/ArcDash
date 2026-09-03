import 'dart:convert';

/// A named set of controller parameters that can be saved, loaded, and applied.
class TuningProfile {
  final String name;
  final String description;

  /// Max speed in km/h (converted to raw RPM when writing).
  final double maxSpeedKph;

  /// Max line current in amps (battery limit).
  final double maxLineCurrA;

  /// Max phase current in amps (motor torque limit).
  final double maxPhaseCurrA;

  /// Regen strength 0.0–1.0.
  final double regenStrength;

  /// ThrottleResponse: 0=Line/Race, 1=Sport, 2=ECO.
  final int throttleResponse;

  /// Low speed (DL) line current scaling (10..100%).
  final double lowSpeedLineCurrPct;

  /// Medium speed (DM) line current scaling (10..100%).
  final double midSpeedLineCurrPct;

  /// Boost mode duration in seconds (0..30s).
  final int boostTimeSeconds;

  /// Low voltage protection cutoff (40..90V).
  final double lowVoltCutoffV;

  /// Over voltage protection cutoff (70..110V).
  final double overVoltCutoffV;

  /// Motor temp protection threshold (70..160 °C).
  final double motorTempLimitC;

  /// Controller/MOSFET temp protection threshold (60..120 °C).
  final double controllerTempLimitC;

  /// Flux weakening current (0..150 A or LD raw).
  final double fluxWeakeningCurrA;

  /// Reverse speed limit percentage (10..100%).
  final double reverseSpeedPct;

  /// 3-point power curve: [(rpm%, torque%), ...] for simplified preview.
  final List<PowerPoint> powerCurve;

  /// 18-point detailed speed curve: 500, 1000, 1500 ... 9000 RPM (0..100%).
  final List<int> speedRatios;

  /// 18-point detailed regen curve: 500, 1000, 1500 ... 9000 RPM (-100..0%).
  final List<int> regenRatios;

  /// Hardware pin assignments (pausePin, sideStandPin, cruisePin, boostPin, etc.).
  final Map<String, int> pinMappings;

  final DateTime createdAt;
  final bool isStock;

  const TuningProfile({
    required this.name,
    required this.description,
    required this.maxSpeedKph,
    required this.maxLineCurrA,
    required this.maxPhaseCurrA,
    required this.regenStrength,
    required this.throttleResponse,
    this.lowSpeedLineCurrPct = 40.0,
    this.midSpeedLineCurrPct = 70.0,
    this.boostTimeSeconds = 10,
    this.lowVoltCutoffV = 60.0,
    this.overVoltCutoffV = 90.7,
    this.motorTempLimitC = 130.0,
    this.controllerTempLimitC = 100.0,
    this.fluxWeakeningCurrA = 40.0,
    this.reverseSpeedPct = 20.0,
    required this.powerCurve,
    this.speedRatios = const [
      100,
      100,
      100,
      100,
      100,
      100,
      100,
      100,
      100,
      100,
      100,
      100,
      100,
      100,
      100,
      100,
      100,
      100
    ],
    this.regenRatios = const [
      -13,
      -16,
      -19,
      -22,
      -25,
      -25,
      -25,
      -25,
      -25,
      -25,
      -25,
      -25,
      -25,
      -25,
      -25,
      -25,
      -25,
      0
    ],
    this.pinMappings = const {
      'pausePin': 0, // NC
      'sideStandPin': 13, // Invalid
      'cruisePin': 13,
      'boostPin': 13,
      'lowSpeedPin': 1, // PIN2
      'highSpeedPin': 2, // PIN3
      'reversePin': 4, // PIN8
      'forwardPin': 13,
    },
    required this.createdAt,
    this.isStock = false,
  });

  // Factory Preset: Arctic Leopard L1E Stock Street Legal (45 km/h, 80A line, 200A phase, StVO-konform, 0 verändert)
  static TuningProfile stockStreetLegal() => TuningProfile(
        name: 'Stock Street Legal',
        description:
            'Original Werks-Setup Arctic Leopard L1E (45 km/h, 80A/200A, StVO-konform, 0 verändert)',
        maxSpeedKph: 45.0,
        maxLineCurrA: 80.0,
        maxPhaseCurrA: 200.0,
        regenStrength: 0.35,
        throttleResponse: 2, // ECO
        lowSpeedLineCurrPct: 40.0,
        midSpeedLineCurrPct: 60.0,
        powerCurve: PowerPoint.smoothCurve(),
        createdAt: DateTime.now(),
        isStock: true,
      );

  // Default Tuned Open Map:
  static TuningProfile defaultTuned() => TuningProfile(
        name: 'Tuned (Offen)',
        description: 'Offenes Fahrprofil (85 km/h, 150A/350A, Sport-Kurve)',
        maxSpeedKph: 85.0,
        maxLineCurrA: 150.0,
        maxPhaseCurrA: 350.0,
        regenStrength: 0.25,
        throttleResponse: 1, // Sport
        powerCurve: PowerPoint.defaultCurve(),
        createdAt: DateTime.now(),
        isStock: false,
      );

  /// L1E baseline presets: only Stock Street Legal is the factory baseline
  static List<TuningProfile> l1ePresets() => [
        stockStreetLegal(),
      ];

  // Factory Preset: Stock Offroad (Arctic Leopard Xe Pro S baseline)
  static TuningProfile stockOffroad() => TuningProfile(
        name: 'Stock Offroad',
        description: 'Original Werks-Setup (125 km/h, 200A/450A, Sport-Kurve)',
        maxSpeedKph: 125.0,
        maxLineCurrA: 200.0,
        maxPhaseCurrA: 450.0,
        regenStrength: 0.25,
        throttleResponse: 1, // Sport
        powerCurve: PowerPoint.defaultCurve(),
        createdAt: DateTime.now(),
        isStock: true,
      );

  // Factory Preset: Street Legal (45 km/h StVO Konform)
  static TuningProfile streetLegal() => TuningProfile(
        name: 'Street Legal',
        description:
            'Verkehrskonforme Drosselung (45 km/h, 80A, Eco-Gasannahme)',
        maxSpeedKph: 45.0,
        maxLineCurrA: 80.0,
        maxPhaseCurrA: 200.0,
        regenStrength: 0.35,
        throttleResponse: 2, // ECO
        lowSpeedLineCurrPct: 40.0,
        midSpeedLineCurrPct: 60.0,
        powerCurve: PowerPoint.smoothCurve(),
        createdAt: DateTime.now(),
        isStock: true,
      );

  // Factory Preset: Eco Range
  static TuningProfile ecoRange() => TuningProfile(
        name: 'Eco Range',
        description:
            'Maximale Reichweite (45 km/h, 100A, sanfte Beschleunigung)',
        maxSpeedKph: 45.0,
        maxLineCurrA: 100.0,
        maxPhaseCurrA: 180.0,
        regenStrength: 0.45,
        throttleResponse: 2, // ECO
        powerCurve: PowerPoint.smoothCurve(),
        createdAt: DateTime.now(),
        isStock: true,
      );

  // Factory Preset: Trail / Enduro
  static TuningProfile trailEnduro() => TuningProfile(
        name: 'Trail / Enduro',
        description:
            'Feinfühliges Ansprechverhalten für schweres Gelände (80 km/h, 140A)',
        maxSpeedKph: 80.0,
        maxLineCurrA: 140.0,
        maxPhaseCurrA: 350.0,
        regenStrength: 0.20,
        throttleResponse: 1, // Sport
        powerCurve: PowerPoint.defaultCurve(),
        createdAt: DateTime.now(),
        isStock: false,
      );

  // Factory Preset: Extreme Sport
  static TuningProfile extremeSport() => TuningProfile(
        name: 'Extreme Sport',
        description:
            'Volle Leistung & Beschleunigung für abgesperrte Strecken (130 km/h, 220A)',
        maxSpeedKph: 130.0,
        maxLineCurrA: 220.0,
        maxPhaseCurrA: 500.0,
        regenStrength: 0.30,
        throttleResponse: 0, // Line/Race
        powerCurve: PowerPoint.aggressiveCurve(),
        createdAt: DateTime.now(),
        isStock: false,
      );

  // User Custom Starting Point
  static TuningProfile custom() => TuningProfile(
        name: 'Custom',
        description: 'Individuell angepasstes Benutzerprofil',
        maxSpeedKph: 65.0,
        maxLineCurrA: 100.0,
        maxPhaseCurrA: 280.0,
        regenStrength: 0.25,
        throttleResponse: 1, // Sport
        powerCurve: PowerPoint.defaultCurve(),
        createdAt: DateTime.now(),
        isStock: false,
      );

  static List<TuningProfile> factoryPresets() => [
        stockOffroad(),
        streetLegal(),
        ecoRange(),
        trailEnduro(),
        extremeSport(),
        custom(),
      ];

  TuningProfile copyWith({
    String? name,
    String? description,
    double? maxSpeedKph,
    double? maxLineCurrA,
    double? maxPhaseCurrA,
    double? regenStrength,
    int? throttleResponse,
    double? lowSpeedLineCurrPct,
    double? midSpeedLineCurrPct,
    int? boostTimeSeconds,
    double? lowVoltCutoffV,
    double? overVoltCutoffV,
    double? motorTempLimitC,
    double? controllerTempLimitC,
    double? fluxWeakeningCurrA,
    double? reverseSpeedPct,
    List<PowerPoint>? powerCurve,
    List<int>? speedRatios,
    List<int>? regenRatios,
    Map<String, int>? pinMappings,
    DateTime? createdAt,
    bool? isStock,
  }) {
    return TuningProfile(
      name: name ?? this.name,
      description: description ?? this.description,
      maxSpeedKph: maxSpeedKph ?? this.maxSpeedKph,
      maxLineCurrA: maxLineCurrA ?? this.maxLineCurrA,
      maxPhaseCurrA: maxPhaseCurrA ?? this.maxPhaseCurrA,
      regenStrength: regenStrength ?? this.regenStrength,
      throttleResponse: throttleResponse ?? this.throttleResponse,
      lowSpeedLineCurrPct: lowSpeedLineCurrPct ?? this.lowSpeedLineCurrPct,
      midSpeedLineCurrPct: midSpeedLineCurrPct ?? this.midSpeedLineCurrPct,
      boostTimeSeconds: boostTimeSeconds ?? this.boostTimeSeconds,
      lowVoltCutoffV: lowVoltCutoffV ?? this.lowVoltCutoffV,
      overVoltCutoffV: overVoltCutoffV ?? this.overVoltCutoffV,
      motorTempLimitC: motorTempLimitC ?? this.motorTempLimitC,
      controllerTempLimitC: controllerTempLimitC ?? this.controllerTempLimitC,
      fluxWeakeningCurrA: fluxWeakeningCurrA ?? this.fluxWeakeningCurrA,
      reverseSpeedPct: reverseSpeedPct ?? this.reverseSpeedPct,
      powerCurve: powerCurve ?? this.powerCurve,
      speedRatios: speedRatios ?? this.speedRatios,
      regenRatios: regenRatios ?? this.regenRatios,
      pinMappings: pinMappings ?? this.pinMappings,
      createdAt: createdAt ?? this.createdAt,
      isStock: isStock ?? this.isStock,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'maxSpeedKph': maxSpeedKph,
        'maxLineCurrA': maxLineCurrA,
        'maxPhaseCurrA': maxPhaseCurrA,
        'regenStrength': regenStrength,
        'throttleResponse': throttleResponse,
        'lowSpeedLineCurrPct': lowSpeedLineCurrPct,
        'midSpeedLineCurrPct': midSpeedLineCurrPct,
        'boostTimeSeconds': boostTimeSeconds,
        'lowVoltCutoffV': lowVoltCutoffV,
        'overVoltCutoffV': overVoltCutoffV,
        'motorTempLimitC': motorTempLimitC,
        'controllerTempLimitC': controllerTempLimitC,
        'fluxWeakeningCurrA': fluxWeakeningCurrA,
        'reverseSpeedPct': reverseSpeedPct,
        'powerCurve': powerCurve.map((p) => p.toJson()).toList(),
        'speedRatios': speedRatios,
        'regenRatios': regenRatios,
        'pinMappings': pinMappings,
        'createdAt': createdAt.toIso8601String(),
        'isStock': isStock,
      };

  factory TuningProfile.fromJson(Map<String, dynamic> json) => TuningProfile(
        name: json['name'] as String,
        description: json['description'] as String,
        maxSpeedKph: (json['maxSpeedKph'] as num).toDouble(),
        maxLineCurrA: (json['maxLineCurrA'] as num).toDouble(),
        maxPhaseCurrA: (json['maxPhaseCurrA'] as num).toDouble(),
        regenStrength: (json['regenStrength'] as num).toDouble(),
        throttleResponse: json['throttleResponse'] as int,
        lowSpeedLineCurrPct:
            (json['lowSpeedLineCurrPct'] as num?)?.toDouble() ?? 40.0,
        midSpeedLineCurrPct:
            (json['midSpeedLineCurrPct'] as num?)?.toDouble() ?? 70.0,
        boostTimeSeconds: (json['boostTimeSeconds'] as num?)?.toInt() ?? 10,
        lowVoltCutoffV: (json['lowVoltCutoffV'] as num?)?.toDouble() ?? 60.0,
        overVoltCutoffV: (json['overVoltCutoffV'] as num?)?.toDouble() ?? 90.7,
        motorTempLimitC: (json['motorTempLimitC'] as num?)?.toDouble() ?? 130.0,
        controllerTempLimitC:
            (json['controllerTempLimitC'] as num?)?.toDouble() ?? 100.0,
        fluxWeakeningCurrA:
            (json['fluxWeakeningCurrA'] as num?)?.toDouble() ?? 40.0,
        reverseSpeedPct: (json['reverseSpeedPct'] as num?)?.toDouble() ?? 20.0,
        powerCurve: (json['powerCurve'] as List)
            .map((p) => PowerPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
        speedRatios: (json['speedRatios'] as List?)?.cast<int>() ??
            const [
              100,
              100,
              100,
              100,
              100,
              100,
              100,
              100,
              100,
              100,
              100,
              100,
              100,
              100,
              100,
              100,
              100,
              100
            ],
        regenRatios: (json['regenRatios'] as List?)?.cast<int>() ??
            const [
              -13,
              -16,
              -19,
              -22,
              -25,
              -25,
              -25,
              -25,
              -25,
              -25,
              -25,
              -25,
              -25,
              -25,
              -25,
              -25,
              -25,
              0
            ],
        pinMappings: (json['pinMappings'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, (v as num).toInt()),
            ) ??
            const {
              'pausePin': 0,
              'sideStandPin': 13,
              'cruisePin': 13,
              'boostPin': 13,
              'lowSpeedPin': 1,
              'highSpeedPin': 2,
              'reversePin': 4,
              'forwardPin': 13,
            },
        createdAt: DateTime.parse(json['createdAt'] as String),
        isStock: json['isStock'] as bool? ?? false,
      );

  String toJsonString() => jsonEncode(toJson());

  factory TuningProfile.fromJsonString(String s) =>
      TuningProfile.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// A point on the 3-point power curve for simplified visualization.
class PowerPoint {
  final double rpmFraction;
  final double torqueFraction;

  const PowerPoint({required this.rpmFraction, required this.torqueFraction});

  static List<PowerPoint> defaultCurve() => const [
        PowerPoint(rpmFraction: 0.0, torqueFraction: 0.6),
        PowerPoint(rpmFraction: 0.5, torqueFraction: 0.85),
        PowerPoint(rpmFraction: 1.0, torqueFraction: 1.0),
      ];

  static List<PowerPoint> smoothCurve() => const [
        PowerPoint(rpmFraction: 0.0, torqueFraction: 0.4),
        PowerPoint(rpmFraction: 0.5, torqueFraction: 0.7),
        PowerPoint(rpmFraction: 1.0, torqueFraction: 0.9),
      ];

  static List<PowerPoint> aggressiveCurve() => const [
        PowerPoint(rpmFraction: 0.0, torqueFraction: 0.9),
        PowerPoint(rpmFraction: 0.5, torqueFraction: 1.0),
        PowerPoint(rpmFraction: 1.0, torqueFraction: 1.0),
      ];

  Map<String, dynamic> toJson() => {
        'rpmFraction': rpmFraction,
        'torqueFraction': torqueFraction,
      };

  factory PowerPoint.fromJson(Map<String, dynamic> json) => PowerPoint(
        rpmFraction: (json['rpmFraction'] as num).toDouble(),
        torqueFraction: (json['torqueFraction'] as num).toDouble(),
      );
}
