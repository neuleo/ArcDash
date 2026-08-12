import 'package:arcdash/models/controller_identity.dart';

enum ParameterRisk { comfort, safetyCritical, hardware }

class ParameterDefinition {
  final String name;
  final int address;
  final int? minRaw;
  final int? maxRaw;
  final int mask;
  final int shift;
  final ParameterRisk risk;
  final bool readable;
  final bool hardwareBoundsConfirmed;

  /// SI-unit bounds of the parameter (e.g. km/h, A). Used by the validator to
  /// reject values outside the hardware envelope before any conversion.
  final double? minPhysical;
  final double? maxPhysical;

  const ParameterDefinition({
    required this.name,
    required this.address,
    required this.minRaw,
    required this.maxRaw,
    this.mask = 0xFFFF,
    this.shift = 0,
    required this.risk,
    required this.readable,
    required this.hardwareBoundsConfirmed,
    this.minPhysical,
    this.maxPhysical,
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
      throw StateError('$name has no confirmed writable bounds');
    }
    return (currentWord & ~mask) | ((checked << shift) & mask);
  }
}

class ParameterCatalog {
  // Limits confirmed from reference/basemaps/unmodified_basemap.json
  // (factory block 0x12 maxSpeed raw 0x2328 = 9000 = 125 km/h -> 72 raw/kph,
  //  block 0x18 maxLineCurrent raw 720 = 180 A -> raw = A * 4).
  static const definitions = <String, ParameterDefinition>{
    'maxSpeed': ParameterDefinition(
      name: 'maxSpeed',
      address: 0x15,
      minRaw: (10 * 72), // 10 km/h
      maxRaw: (130 * 72), // 130 km/h
      risk: ParameterRisk.safetyCritical,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 10,
      maxPhysical: 130,
    ),
    'maxLineCurrent': ParameterDefinition(
      name: 'maxLineCurrent',
      address: 0x19,
      minRaw: 40, // 10 A * 4
      maxRaw: 1200, // 300 A * 4
      risk: ParameterRisk.safetyCritical,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 10,
      maxPhysical: 300,
    ),
    'throttleResponse': ParameterDefinition(
      name: 'throttleResponse',
      address: 0x1A,
      minRaw: 0,
      maxRaw: 3, // 2-bit field, bits 2-3
      mask: 0x000C,
      shift: 2,
      risk: ParameterRisk.hardware,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0,
      maxPhysical: 3,
    ),
    'maxPhaseCurrent': ParameterDefinition(
      name: 'maxPhaseCurrent',
      address: 0x1B,
      minRaw: 80, // 20 A * 4
      maxRaw: 2000, // 500 A * 4
      risk: ParameterRisk.safetyCritical,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 20,
      maxPhysical: 500,
    ),
    'lowSpeedLineCurr': ParameterDefinition(
      name: 'lowSpeedLineCurr',
      address: 0x11,
      minRaw: 10,
      maxRaw: 100,
      risk: ParameterRisk.comfort,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 10,
      maxPhysical: 100,
    ),
    'midSpeedLineCurr': ParameterDefinition(
      name: 'midSpeedLineCurr',
      address: 0x13,
      minRaw: 10,
      maxRaw: 100,
      risk: ParameterRisk.comfort,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 10,
      maxPhysical: 100,
    ),
    'boostTime': ParameterDefinition(
      name: 'boostTime',
      address: 0x22,
      minRaw: 0,
      maxRaw: 30,
      risk: ParameterRisk.hardware,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0,
      maxPhysical: 30,
    ),
    'lowVoltCutoff': ParameterDefinition(
      name: 'lowVoltCutoff',
      address: 0x0E,
      minRaw: 500, // 50V * 10
      maxRaw: 800, // 80V * 10
      risk: ParameterRisk.hardware,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 50,
      maxPhysical: 80,
    ),
    'overVoltCutoff': ParameterDefinition(
      name: 'overVoltCutoff',
      address: 0x0F,
      minRaw: 800, // 80V * 10
      maxRaw: 1000, // 100V * 10
      risk: ParameterRisk.hardware,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 80,
      maxPhysical: 100,
    ),
    'motorTempLimit': ParameterDefinition(
      name: 'motorTempLimit',
      address: 0x16,
      minRaw: 80,
      maxRaw: 150,
      risk: ParameterRisk.hardware,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 80,
      maxPhysical: 150,
    ),
    'controllerTempLimit': ParameterDefinition(
      name: 'controllerTempLimit',
      address: 0x17,
      minRaw: 60,
      maxRaw: 110,
      risk: ParameterRisk.hardware,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 60,
      maxPhysical: 110,
    ),
    'fluxWeakeningCurr': ParameterDefinition(
      name: 'fluxWeakeningCurr',
      address: 0x25,
      minRaw: 0,
      maxRaw: 150,
      risk: ParameterRisk.hardware,
      readable: true,
      hardwareBoundsConfirmed: true,
      minPhysical: 0,
      maxPhysical: 150,
    ),
  };

  const ParameterCatalog();

  ParameterDefinition operator [](String name) {
    final definition = definitions[name];
    if (definition == null) throw ArgumentError.value(name, 'name');
    return definition;
  }
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
  if (decision.allowed) return 'Write authorized';
  final reasons = <String>{
    for (final rejection in decision.rejections)
      switch (rejection) {
        SafetyRejection.disconnected => 'Controller not connected',
        SafetyRejection.unknownIdentity => 'Controller identity unverified',
        SafetyRejection.staleTelemetry => 'Telemetry is stale',
        SafetyRejection.insufficientSamples => 'Not enough stillness samples',
        SafetyRejection.moving => 'Vehicle moving',
        SafetyRejection.motorRunning => 'Motor running',
        SafetyRejection.faultActive => 'Controller fault active',
        SafetyRejection.directionUnknown => 'Direction unknown',
        SafetyRejection.brakeActive => 'Brake active',
        SafetyRejection.throttleNotZero => 'Throttle not zero',
        SafetyRejection.missingBackup => 'No verified stock backup',
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
