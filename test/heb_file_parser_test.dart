import 'dart:io';
import 'package:arcdash/services/heb_file_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps the 26 FarDriver blocks and preserves CAN configuration bytes',
      () {
    final bytes =
        List<int>.generate(HebFile.expectedLength, (index) => index & 0xFF);
    final heb = HebFile.parse(bytes);

    expect(heb.blocks, hasLength(26));
    expect(heb.block(0x00), bytes.sublist(0, 12));
    expect(heb.block(0x12), bytes.sublist(36, 48));
    expect(heb.block(0xD0), bytes.sublist(300, 312));
    expect(heb.canConfiguration, bytes.sublist(312));
  });

  test('rejects truncated, extended, and unknown block access', () {
    expect(() => HebFile.parse(List.filled(695, 0)), throwsFormatException);
    expect(() => HebFile.parse(List.filled(697, 0)), throwsFormatException);
    expect(() => HebFile.parse(List.filled(696, 0)).block(0x01),
        throwsArgumentError);
  });

  test(
      'parses l1e_unmodified_basemap.heb asset and confirms L1E 45 km/h parameters',
      () {
    final file = File('assets/basemaps/l1e_unmodified_basemap.heb');
    expect(file.existsSync(), isTrue);
    final heb = HebFile.parse(file.readAsBytesSync());
    expect(heb.blocks, hasLength(26));

    // Block 0x12, word 3 (0x15) is MaxSpeed (3480 RPM for 45 km/h limiter)
    final b12 = heb.block(0x12);
    final maxSpeed = b12[6] | (b12[7] << 8);
    expect(maxSpeed, 3480);

    // Block 0x18, word 1 (0x19) is MaxLineCurrent (470 raw = 117.5 A)
    final b18 = heb.block(0x18);
    final maxLineCurr = b18[2] | (b18[3] << 8);
    expect(maxLineCurr, 470);
  });
}
