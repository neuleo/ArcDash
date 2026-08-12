import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/fardriver_memory.dart';

void main() {
  group('FarDriver 26-Block Memory Model Tests', () {
    test('Addr00Block decodes and preserves calibration words', () {
      final raw = List<int>.filled(12, 0);
      raw[0] = 0x00;
      raw[1] = 0x01; // volCoeff = 256
      raw[4] = 0x11;
      raw[5] = 0x01; // phaseACoeff = 273
      raw[6] = 0xB7;
      raw[7] = 0x01; // lineCoeff = 439
      final block = Addr00Block.fromRaw(raw);
      expect(block.volCoeff, 256);
      expect(block.phaseACoeff, 273);
      expect(block.lineCoeff, 439);
      expect(block.toRaw(), raw);
    });

    test('Addr06Block decodes throttle voltages and bitfields', () {
      final raw = List<int>.filled(12, 0);
      raw[4] = 18; // 18 / 20 = 0.9V
      raw[5] = 75; // 75 / 20 = 3.75V
      raw[10] = 0x62; // tempSensor = 6 (NTC10K), brakeConfig = 2 (P_StopGnd)
      raw[11] = 0x08; // pc13RaceResponse = 1 (bit 3)
      final block = Addr06Block.fromRaw(raw);
      expect(block.throttleLowVoltage, 0.9);
      expect(block.throttleHighVoltage, 3.75);
      expect(block.tempSensor, 6);
      expect(block.brakeConfig, 2);
      expect(block.pc13RaceResponse, isTrue);

      final updated = block.withThrottleVoltages(low: 1.0, high: 4.0);
      expect(updated.throttleLowVoltage, 1.0);
      expect(updated.throttleHighVoltage, 4.0);
    });

    test('Addr12Block decodes maxSpeed and ratedVoltage', () {
      final raw = List<int>.filled(12, 0);
      raw[4] = 4; // polePairs
      raw[6] = 0x28;
      raw[7] = 0x23; // maxSpeed = 9000
      raw[10] = 0xD0;
      raw[11] = 0x02; // ratedVoltage = 720 (72.0 V)
      final block = Addr12Block.fromRaw(raw);
      expect(block.polePairs, 4);
      expect(block.maxSpeed, 9000);
      expect(block.ratedVoltageV, 72.0);
    });

    test('Addr18Block decodes and updates line current & throttle response',
        () {
      final raw = List<int>.filled(12, 0);
      raw[2] = 0xD0;
      raw[3] = 0x02; // maxLineCurrent = 720 (180 A)
      raw[4] = 0x04; // throttleResponse = 1 (Sport, bit 2-3)
      final block = Addr18Block.fromRaw(raw);
      expect(block.maxLineCurrentAmps, 180.0);
      expect(block.throttleResponse, 1);

      final updated =
          block.withMaxLineCurrentAmps(200.0).withThrottleResponse(2);
      expect(updated.maxLineCurrentAmps, 200.0);
      expect(updated.throttleResponse, 2);
    });

    test('Addr69Block decodes pin mappings and limit speed', () {
      final raw = List<int>.filled(12, 0);
      raw[0] = 0xD0; // sideStand = 13 (Invalid), pause = 0 (NC)
      raw[1] = 0xDD; // boost = 13, cruise = 13
      raw[2] = 0x21; // highSpeed = 2 (PIN3), lowSpeed = 1 (PIN2)
      raw[3] = 0xD4; // forward = 13, reverse = 4 (PIN8)
      raw[6] = 0x28;
      raw[7] = 0x23; // limitSpeed = 9000
      final block = Addr69Block.fromRaw(raw);
      expect(block.pausePin, 0);
      expect(block.sideStandPin, 13);
      expect(block.lowSpeedPin, 1);
      expect(block.highSpeedPin, 2);
      expect(block.reversePin, 4);
      expect(block.limitSpeedRPM, 9000);
    });

    test('Addr88Block and Addr8EBlock decode and update speed curves', () {
      final b88 = Addr88Block.empty();
      expect(b88.ratios.length, 12);
      expect(b88.ratio500, 100);

      final b8E = Addr8EBlock.empty();
      final updated8E = b8E.withRegenRatios([-13, -16, -19, -22]);
      expect(updated8E.nratio0, -13);
      expect(updated8E.nratio1, -16);
      expect(updated8E.nratio2, -19);
      expect(updated8E.nratio3, -22);
    });

    test('FarDriverFullMemory handles all 26 blocks', () {
      final memory = FarDriverFullMemory.empty();
      expect(FarDriverFullMemory.blockAddresses.length, 26);
      expect(memory.addr12.maxSpeed, 0);

      final b12 = Addr12Block.empty().withMaxSpeed(9000);
      memory.setBlockRaw(0x12, b12.toRaw());
      expect(memory.addr12.maxSpeed, 9000);
    });
  });
}
