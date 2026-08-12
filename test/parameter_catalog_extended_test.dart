import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/services/write_safety.dart';

void main() {
  group('Extended Parameter Catalog Tests', () {
    const catalog = ParameterCatalog();

    test('catalog contains all essential categories', () {
      expect(catalog.forCategory(ParameterCategory.motor).isNotEmpty, isTrue);
      expect(
          catalog.forCategory(ParameterCategory.gearRatios).isNotEmpty, isTrue);
      expect(catalog.forCategory(ParameterCategory.regen).isNotEmpty, isTrue);
      expect(catalog.forCategory(ParameterCategory.protect).isNotEmpty, isTrue);
      expect(catalog.forCategory(ParameterCategory.pid).isNotEmpty, isTrue);
      expect(catalog.forCategory(ParameterCategory.display).isNotEmpty, isTrue);
    });

    test('validates physical ranges correctly for motor parameters', () {
      final maxSpeed = catalog['maxSpeed'];
      expect(maxSpeed.inPhysicalRange(120), isTrue);
      expect(maxSpeed.inPhysicalRange(5), isFalse);
      expect(maxSpeed.inPhysicalRange(180), isFalse);

      final maxLineCurrent = catalog['maxLineCurrent'];
      expect(maxLineCurrent.inPhysicalRange(180), isTrue);
      expect(maxLineCurrent.inPhysicalRange(350), isFalse);
    });

    test('validates bitfield masking and word application', () {
      final throttleResponse = catalog['throttleResponse'];
      const originalWord = 0x0000;
      final updatedWord = throttleResponse.applyToWord(
          originalWord, 2); // ECO (mode 2, bits 2-3 -> 0x08)
      expect(updatedWord, 0x08);

      final sportWord = throttleResponse.applyToWord(
          updatedWord, 1); // Sport (mode 1, bits 2-3 -> 0x04)
      expect(sportWord, 0x04);
    });

    test('validates voltage cutoff protections', () {
      final lvc = catalog['lowVoltCutoff'];
      expect(lvc.minPhysical, 40);
      expect(lvc.maxPhysical, 90);

      final ovp = catalog['overVoltCutoff'];
      expect(ovp.minPhysical, 70);
      expect(ovp.maxPhysical, 110);
    });
  });
}
