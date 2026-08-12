import 'dart:convert';

import 'package:arcdash/models/versioned_profile.dart';
import 'package:arcdash/services/write_safety.dart';

ParameterDefinition? _definitionFor(String name) => switch (name) {
      'maxSpeedKph' => ParameterCatalog.definitions['maxSpeed'],
      'maxLineCurrA' => ParameterCatalog.definitions['maxLineCurrent'],
      'maxPhaseCurrA' => ParameterCatalog.definitions['maxPhaseCurrent'],
      'throttleResponse' => ParameterCatalog.definitions['throttleResponse'],
      'lowSpeedLineCurr' => ParameterCatalog.definitions['lowSpeedLineCurr'],
      'midSpeedLineCurr' => ParameterCatalog.definitions['midSpeedLineCurr'],
      'boostTime' => ParameterCatalog.definitions['boostTime'],
      'lowVoltCutoff' => ParameterCatalog.definitions['lowVoltCutoff'],
      'overVoltCutoff' => ParameterCatalog.definitions['overVoltCutoff'],
      'motorTempLimit' => ParameterCatalog.definitions['motorTempLimit'],
      'controllerTempLimit' =>
        ParameterCatalog.definitions['controllerTempLimit'],
      'fluxWeakeningCurr' => ParameterCatalog.definitions['fluxWeakeningCurr'],
      _ => null,
    };

enum ProfileIssue { invalidName, unknownParameter, invalidValue, unknownBounds }

class ProfileValidation {
  final Set<ProfileIssue> issues;

  const ProfileValidation(this.issues);

  bool get valid => issues.isEmpty;
}

class ProfileValidator {
  const ProfileValidator();

  ProfileValidation validate(VersionedProfile profile) {
    return validateParameters(profile.parameters);
  }

  ProfileValidation validateParameters(Map<String, Object?> parameters) {
    final issues = <ProfileIssue>{};
    for (final entry in parameters.entries) {
      final definition = _definitionFor(entry.key);
      // Parameters without a catalog entry (e.g. maxPhaseCurrA, regenStrength)
      // are display-only and never written, so they are not validated.
      if (definition == null) continue;
      if (entry.value is! num) {
        issues.add(ProfileIssue.invalidValue);
      } else if (!definition.hardwareBoundsConfirmed) {
        issues.add(ProfileIssue.unknownBounds);
      } else if (!definition.inPhysicalRange(entry.value as num)) {
        issues.add(ProfileIssue.invalidValue);
      }
    }
    return ProfileValidation(Set.unmodifiable(issues));
  }
}

enum ProfileDiffRisk { normal, critical, unknown }

class ProfileValueDiff {
  final String parameter;
  final Object? before;
  final Object? after;
  final ProfileDiffRisk risk;

  const ProfileValueDiff({
    required this.parameter,
    required this.before,
    required this.after,
    required this.risk,
  });
}

class ProfileDiff {
  final List<ProfileValueDiff> changes;

  const ProfileDiff(this.changes);

  bool get isEmpty => changes.isEmpty;
}

class ProfileDiffBuilder {
  const ProfileDiffBuilder();

  ProfileDiff compare(VersionedProfile before, VersionedProfile after) {
    final names = {...before.parameters.keys, ...after.parameters.keys}.toList()
      ..sort();
    final changes = <ProfileValueDiff>[];
    for (final name in names) {
      final oldValue = before.parameters[name];
      final newValue = after.parameters[name];
      if (oldValue == newValue) continue;
      final definition = _definitionFor(name);
      changes.add(ProfileValueDiff(
        parameter: name,
        before: oldValue,
        after: newValue,
        risk: definition == null && name == 'maxPhaseCurrA'
            ? ProfileDiffRisk.critical
            : definition == null
                ? ProfileDiffRisk.unknown
                : definition.risk == ParameterRisk.safetyCritical
                    ? ProfileDiffRisk.critical
                    : ProfileDiffRisk.normal,
      ));
    }
    return ProfileDiff(List.unmodifiable(changes));
  }
}

class ProfileCodec {
  static const format = 'arcdash-profile-v1';

  static String encode(VersionedProfile profile) => jsonEncode({
        'format': format,
        'schemaVersion': 1,
        'profile': profile.toJson(),
      });

  static VersionedProfile decode(String content) {
    final value = jsonDecode(content);
    if (value is! Map<String, dynamic> ||
        value['format'] != format ||
        value['schemaVersion'] != 1 ||
        value['profile'] is! Map) {
      throw const FormatException('unsupported profile format');
    }
    return VersionedProfile.fromJson(
        Map<String, dynamic>.from(value['profile'] as Map));
  }
}
