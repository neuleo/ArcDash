import 'package:arcdash/services/bluetooth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isBikeHardwareName', () {
    test('matches FarDriver tuner dongles', () {
      for (final name in [
        'CONTROL-1234',
        'DMC-5678',
        'CONTROLDMC',
        'FarDriver-01',
        'YuanQ-88',
        'FOC-02',
        'BT05',
        'JDY-31',
        'HM-10',
        'HM10',
      ]) {
        expect(isBikeHardwareName(name), isTrue, reason: name);
      }
    });

    test('matches ANT BMS modules', () {
      for (final name in [
        'ANT-BMS',
        'BMS-001',
        'ANT-BMS-PRO',
        'ANT',
      ]) {
        expect(isBikeHardwareName(name), isTrue, reason: name);
      }
    });

    test('is case-insensitive', () {
      expect(isBikeHardwareName('control_01'), isTrue);
      expect(isBikeHardwareName('fardriver'), isTrue);
      expect(isBikeHardwareName('jdy-31'), isTrue);
      expect(isBikeHardwareName('ant-bms'), isTrue);
    });

    test('rejects unrelated consumer devices', () {
      for (final name in [
        'TV',
        'JBL Speaker',
        'Sony WH-1000XM4',
        'Samsung TV',
        'Philips Hue',
        'Aqara Gateway',
        'Smart Bulb',
        'AirPods Pro',
        'Unbenanntes BLE Gerät (AA:BB:CC:DD:EE:FF)',
      ]) {
        expect(isBikeHardwareName(name), isFalse, reason: name);
      }
    });
  });
}
