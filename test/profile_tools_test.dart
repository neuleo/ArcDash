import 'package:arcdash/models/versioned_profile.dart';
import 'package:arcdash/services/profile_tools.dart';
import 'package:flutter_test/flutter_test.dart';

VersionedProfile _profile({double speed = 45}) => VersionedProfile(
      id: 'p',
      name: 'Profile',
      description: '',
      parameters: {
        'maxSpeedKph': speed,
        'maxLineCurrA': 60.0,
        'maxPhaseCurrA': 120.0,
        'regenStrength': 0.3,
        'throttleResponse': 1,
      },
      source: ProfileSource.user,
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  test('profile editor validation accepts in-range hardware bounds', () {
    final validation = const ProfileValidator().validate(_profile());
    expect(validation.valid, isTrue);
    expect(validation.issues, isEmpty);
  });

  test('profile editor validation rejects values outside hardware bounds', () {
    final tooFast = _profile(speed: 200);
    expect(const ProfileValidator().validate(tooFast).valid, isFalse);
    expect(const ProfileValidator().validate(tooFast).issues,
        contains(ProfileIssue.invalidValue));

    final tooSlow = _profile(speed: 5);
    expect(const ProfileValidator().validate(tooSlow).issues,
        contains(ProfileIssue.invalidValue));
  });

  test('diff sorts values and classifies safety-critical fields', () {
    final diff =
        const ProfileDiffBuilder().compare(_profile(), _profile(speed: 50));
    expect(diff.changes.single.parameter, 'maxSpeedKph');
    expect(diff.changes.single.risk, ProfileDiffRisk.critical);
  });

  test('profile JSON round-trip rejects unknown format', () {
    final content = ProfileCodec.encode(_profile());
    expect(ProfileCodec.decode(content).id, 'p');
    expect(
        () => ProfileCodec.decode('{"format":"other"}'), throwsFormatException);
  });
}
