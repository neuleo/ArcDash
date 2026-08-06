import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/utils/packet_parser.dart';
import 'package:arcdash/utils/crc_calculator.dart';

void main() {
  group('PacketParser', () {
    test('extractPackets extracts 16-byte and 8-byte valid packets from stream',
        () {
      final p16 = Uint8List(16);
      p16[0] = 0xAA;
      p16[1] = 0x00; // mapped address ID 0 -> 0xE2
      CrcCalculator.computeCRC(p16, 16);

      final p8 = Uint8List(8);
      p8[0] = 0xAA;
      p8[1] = 0x46;
      CrcCalculator.computeCRC(p8, 8);

      // Separate packets with noise
      final stream16 = <int>[0xFF, 0x00, ...p16, 0x55];
      final extracted16 = PacketParser.extractPackets(stream16);
      expect(extracted16.length, 1);
      expect(extracted16[0].length, 16);

      final stream8 = <int>[0xFF, ...p8, 0x12];
      final extracted8 = PacketParser.extractPackets(stream8);
      expect(extracted8.length, 1);
      expect(extracted8[0].length, 8);
    });

    test('parseStatusPacket parses address and raw data correctly', () {
      final p16 = Uint8List(16);
      p16[0] = 0xAA;
      p16[1] = 0x01; // mapped address ID 1 -> 0xE8
      p16[2] = 0x01; // Data byte 0
      p16[13] = 0xFF; // Data byte 11
      CrcCalculator.computeCRC(p16, 16);

      final parsed = PacketParser.parseStatusPacket(p16);
      expect(parsed, isNotNull);
      expect(parsed!.address, 0xE8);
      expect(parsed.rawData.length, 12);
      expect(parsed.rawData[0], 0x01);
      expect(parsed.rawData[11], 0xFF);
    });

    test('parseStatusPacket rejects invalid packet length or CRC', () {
      final invalid = [0xAA, 0x01, 0x00];
      expect(PacketParser.parseStatusPacket(invalid), isNull);

      final badCrc = Uint8List(16);
      badCrc[0] = 0xAA;
      badCrc[1] = 0x01;
      expect(PacketParser.parseStatusPacket(badCrc), isNull);
    });

    test('parseStatusPacket maps high-bit packet IDs via the lower 7 bits', () {
      // Live FarDriver status frames set the protocol flag bits, so byte 1
      // arrives as 0x80–0xB6. 0x85 must map to index 5 -> flashReadAddr[5]
      // = 0x0C (battery calibration), never to the speed block 0xE2.
      List<int> packetFor(int idByte) {
        final p = Uint8List(16);
        p[0] = 0xAA;
        p[1] = idByte;
        CrcCalculator.computeCRC(p, 16);
        return p;
      }

      expect(PacketParser.parseStatusPacket(packetFor(0x85))!.address, 0x0C);
      expect(PacketParser.parseStatusPacket(packetFor(0x80))!.address, 0xE2);
      expect(PacketParser.parseStatusPacket(packetFor(0xB6))!.address, 0xFA);
    });

    test('high-bit status ID decodes the mapped telemetry block end to end',
        () {
      // Full pipeline: raw frame (0xAA 0x85 ...) -> parse -> extract.
      // Index 5 is the 0x0C battery-calibration block, not 0xE2 speed/flags.
      final p = Uint8List(16);
      p[0] = 0xAA;
      p[1] = 0x85;
      // rawData[2..3] = zeroBattCoeff = 600 (0x0258)
      p[4] = 0x58;
      p[5] = 0x02;
      // rawData[4..5] = fullBattCoeff = 840 (0x0348)
      p[6] = 0x48;
      p[7] = 0x03;
      CrcCalculator.computeCRC(p, 16);

      final parsed = PacketParser.parseStatusPacket(p);
      expect(parsed, isNotNull);
      expect(parsed!.address, 0x0C);
      final update = PacketParser.extractTelemetry(parsed);
      expect(update, isNotNull);
      expect(update!.zeroBattCoeff, 600);
      expect(update.fullBattCoeff, 840);
    });

    test('readInt16LE and readUint16LE read signed/unsigned 16-bit values', () {
      final data = [0xFF, 0x7F, 0x00, 0x80]; // 32767, -32768
      expect(PacketParser.readUint16LE(data, 0), 32767);
      expect(PacketParser.readInt16LE(data, 0), 32767);

      expect(PacketParser.readUint16LE(data, 2), 32768);
      expect(PacketParser.readInt16LE(data, 2), -32768);
    });

    test('readPhaseCurrent converts 24-bit value to phase current', () {
      final data = [
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x64
      ]; // raw = 100 -> sqrt(100) = 10 -> 19.53125 A
      final curr = PacketParser.readPhaseCurrent(data, 3);
      expect(curr, closeTo(19.53125, 0.001));
    });

    test('toHexString formats byte list into uppercase hex string', () {
      expect(PacketParser.toHexString([0xAA, 0x08, 0xFF]), 'AA 08 FF');
    });

    test('flashReadAddr mapping contains valid table entries', () {
      expect(flashReadAddr.length, 55);
      expect(flashReadAddr[0], 0xE2);
      expect(flashReadAddr[1], 0xE8);
      expect(flashReadAddr[5], 0x0C);
      expect(flashReadAddr[54], 0xFA);
    });
  });
}
