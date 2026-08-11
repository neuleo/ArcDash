import 'dart:convert';

/// A named set of controller parameters that can be saved, loaded, and applied.
class TuningProfile {
  final String name;
  final String description;

  /// Max speed in km/h (converted to raw RPM when writing).
  final double maxSpeedKph;

  /// Max line current in amps.
  final double maxLineCurrA;

  /// Max phase current in amps (stored for display; derived from phase coeff).
  final double maxPhaseCurrA;

  /// Regen strength 0.0–1.0.
  final double regenStrength;

  /// ThrottleResponse: 0=Line/Race, 1=Sport, 2=ECO.
  final int throttleResponse;

  /// 3-point power curve: [(rpm%, torque%), ...] for low/mid/high.
  final List<PowerPoint> powerCurve;

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
    required this.powerCurve,
    required this.createdAt,
    this.isStock = false,
  });

  // Built-in / factory presets (Phase 14, T091).
  // Values and bounds are derived from the verified factory baseline
  // `reference/basemaps/unmodified_basemap.json` / `assets/basemaps/...heb`.
  static TuningProfile stockOffroad() => TuningProfile(
        name: 'Stock Offroad',
        description: 'Factory off-road baseline (125 km/h, 200 A, Sport)',
        maxSpeedKph: 125.0,
        maxLineCurrA: 200.0,
        maxPhaseCurrA: 300.0,
        regenStrength: 0.1,
        throttleResponse: 1, // Sport
        powerCurve: PowerPoint.defaultCurve(),
        createdAt: DateTime.now(),
        isStock: true,
      );

  static TuningProfile ecoRange() => TuningProfile(
        name: 'Eco Range',
        description: 'Maximum range — gentle power (45 km/h, 100 A, Eco)',
        maxSpeedKph: 45.0,
        maxLineCurrA: 100.0,
        maxPhaseCurrA: 150.0,
        regenStrength: 0.4,
        throttleResponse: 2, // Eco
        powerCurve: PowerPoint.smoothCurve(),
        createdAt: DateTime.now(),
        isStock: true,
      );

  static TuningProfile custom() => TuningProfile(
        name: 'Custom',
        description: 'User-defined starting point',
        maxSpeedKph: 65.0,
        maxLineCurrA: 100.0,
        maxPhaseCurrA: 200.0,
        regenStrength: 0.2,
        throttleResponse: 1, // Sport
        powerCurve: PowerPoint.defaultCurve(),
        createdAt: DateTime.now(),
        isStock: false,
      );

  /// All factory presets shown in the tuning UI. User-created presets are the
  /// same type but persisted via [StorageService] and shown alongside these.
  static List<TuningProfile> factoryPresets() =>
      [stockOffroad(), ecoRange(), custom()];

  TuningProfile copyWith({
    String? name,
    String? description,
    double? maxSpeedKph,
    double? maxLineCurrA,
    double? maxPhaseCurrA,
    double? regenStrength,
    int? throttleResponse,
    List<PowerPoint>? powerCurve,
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
      powerCurve: powerCurve ?? this.powerCurve,
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
        'powerCurve': powerCurve.map((p) => p.toJson()).toList(),
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
        powerCurve: (json['powerCurve'] as List)
            .map((p) => PowerPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        isStock: json['isStock'] as bool? ?? false,
      );

  String toJsonString() => jsonEncode(toJson());

  factory TuningProfile.fromJsonString(String s) =>
      TuningProfile.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// A point on the 3-point power curve.
class PowerPoint {
  /// RPM fraction 0.0–1.0 (low / mid / high).
  final double rpmFraction;

  /// Torque fraction 0.0–1.0.
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
