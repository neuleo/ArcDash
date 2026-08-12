import 'package:arcdash/utils/crc_calculator.dart';

/// Known memory addresses for FarDriver protocol.
class FardriverAddr {
  static const int volCoeff = 0x00;
  static const int speedKP_KI = 0x07;
  static const int throttleLowHigh = 0x08;
  static const int phaseOffset = 0x0C;
  static const int maxSpeed = 0x15;
  static const int ratedPower = 0x16;
  static const int ratedVoltage = 0x17;
  static const int ratedSpeed = 0x18;
  static const int maxLineCurr = 0x19;
  static const int throttleResponse = 0x1A;
  static const int maxPhaseCurr = 0x1B;
  static const int lowVolCutoff = 0x1F;
  static const int highVolCutoff = 0x25;
  static const int boostLineCurr = 0x26;
  static const int boostPhaseCurr = 0x27;
  static const int backSpeed = 0x28;
  static const int lowSpeedLinePhase = 0x32;
  static const int midSpeedLinePhase = 0x33;
  static const int stopBackCurr = 0x30;
  static const int maxBackCurr = 0x31;
  static const int tempLimits = 0x84;
  static const int speedCurveMin5500 = 0x88;
  static const int speedCurve6000Max = 0x8E;
  static const int regenCurve4_15 = 0x94;
  static const int regenCurve16_19 = 0x9A;
  static const int sysCmd = 0xA0;
  static const int polePairs = 0x14;
}

/// System command values written to address 0xA0 with prefix 0x88.
class SysCmd {
  static const int nonFollowingStatus = 0x01;
  static const int startSelfLearn = 0x02;
  static const int stopBalance = 0x03;
  static const int resetController = 0x05;
  static const int startDataGather = 0x06;
  static const int factoryReset = 0x08;
}

class ProtocolService {
  /// Builds the 8-byte write packet used to set a 16-bit value at [addr].
  ///
  /// Format: [0xAA][0x46][addr][addr][lo][hi][crc0][crc1]
  /// compute_length = 6 = (8 - 2), flags = 1 (bit 6 set → 0x40), so byte1 = 6 | 0x40 = 0x46
  static List<int> buildWritePacket(int addr, int value) {
    final packet = List<int>.filled(8, 0);
    packet[0] = 0xAA;
    packet[1] = 0x46; // compute_length=6, flags=1 (write)
    packet[2] = addr & 0xFF;
    packet[3] = addr & 0xFF; // addr_confirm = same addr
    packet[4] = value & 0xFF; // data low byte
    packet[5] = (value >> 8) & 0xFF; // data high byte
    CrcCalculator.computeCRC(packet, 8);
    return packet;
  }

  /// Builds a write packet with two explicit data bytes (not a single uint16).
  static List<int> buildWritePacket16(int addr, int byte0, int byte1) {
    final packet = List<int>.filled(8, 0);
    packet[0] = 0xAA;
    packet[1] = 0x46;
    packet[2] = addr & 0xFF;
    packet[3] = addr & 0xFF;
    packet[4] = byte0 & 0xFF;
    packet[5] = byte1 & 0xFF;
    CrcCalculator.computeCRC(packet, 8);
    return packet;
  }

  /// Builds a multi-byte block write packet.
  /// Format: [0xAA] [0xC0 + len + 4] [addr] [addr] [data...] [crc0] [crc1]
  static List<int> buildBlockWritePacket(int addr, List<int> data) {
    final totalLen =
        data.length + 6; // 0xAA, header, addr, addr, data..., crc0, crc1
    final packet = List<int>.filled(totalLen, 0);
    packet[0] = 0xAA;
    packet[1] = 0xC0 + (data.length + 4);
    packet[2] = addr & 0xFF;
    packet[3] = addr & 0xFF;
    for (var i = 0; i < data.length; i++) {
      packet[4 + i] = data[i] & 0xFF;
    }
    CrcCalculator.computeCRC(packet, totalLen);
    return packet;
  }

  /// Builds the system command packet (writes [0x88, cmd] to address 0xA0).
  static List<int> buildSysCmd(int cmd) {
    return buildWritePacket16(FardriverAddr.sysCmd, 0x88, cmd);
  }

  /// Packet to start status streaming (non-following status mode).
  static List<int> startStatusStreamPacket() =>
      buildSysCmd(SysCmd.nonFollowingStatus);

  /// Packet to trigger controller reboot/reset.
  static List<int> resetControllerPacket() =>
      buildSysCmd(SysCmd.resetController);

  /// Packet to restore factory defaults.
  static List<int> factoryResetPacket() => buildSysCmd(SysCmd.factoryReset);

  /// Sets the max line current. [amps] is the desired value in A.
  /// Raw value = amps * 4.
  static List<int> setMaxLineCurrPacket(double amps) {
    final raw = (amps * 4).round().clamp(0, 0xFFFF);
    return buildWritePacket(FardriverAddr.maxLineCurr, raw);
  }

  /// Sets max phase current. [amps] is the desired value in A.
  /// Raw value = amps * 4.
  static List<int> setMaxPhaseCurrPacket(double amps) {
    final raw = (amps * 4).round().clamp(0, 0xFFFF);
    return buildWritePacket(FardriverAddr.maxPhaseCurr, raw);
  }

  /// Sets max speed. [maxSpeedRaw] is the raw uint16 RPM value.
  static List<int> setMaxSpeedPacket(int maxSpeedRaw) {
    return buildWritePacket(
        FardriverAddr.maxSpeed, maxSpeedRaw.clamp(0, 0xFFFF));
  }

  /// Sets throttle response mode: 0=Line, 1=Sport, 2=ECO.
  static List<int> setThrottleResponsePacket(int mode) {
    final val = (mode & 0x03) << 2;
    return buildWritePacket(FardriverAddr.throttleResponse, val);
  }

  /// Sets low voltage cutoff in Volts (0.1V resolution).
  static List<int> setLowVolCutoffPacket(double volts) {
    final raw = (volts * 10.0).round().clamp(0, 0xFFFF);
    return buildWritePacket(FardriverAddr.lowVolCutoff, raw);
  }

  /// Sets high voltage cutoff in Volts (0.1V resolution).
  static List<int> setHighVolCutoffPacket(double volts) {
    final raw = (volts * 10.0).round().clamp(0, 0xFFFF);
    return buildWritePacket(FardriverAddr.highVolCutoff, raw);
  }

  /// Sets boost mode line & phase currents in Amps.
  static List<int> setBoostLineCurrPacket(double lineAmps) {
    final raw = (lineAmps * 4.0).round().clamp(0, 0xFFFF);
    return buildWritePacket(FardriverAddr.boostLineCurr, raw);
  }

  static List<int> setBoostPhaseCurrPacket(double phaseAmps) {
    final raw = (phaseAmps * 4.0).round().clamp(0, 0xFFFF);
    return buildWritePacket(FardriverAddr.boostPhaseCurr, raw);
  }

  /// Converts a desired speed in km/h to a raw MaxSpeed RPM value.
  static int kphToMaxSpeedRaw({
    required double kph,
    required int wheelRadius,
    required int wheelWidth,
    required int wheelRatio,
    required int rateRatio,
  }) {
    final factor = 0.00376991136 *
        (wheelRadius * 1270.0 + wheelWidth * wheelRatio) /
        rateRatio;
    if (factor <= 0 || factor.isNaN || factor.isInfinite) return 0;
    return (kph / factor).round().clamp(0, 0xFFFF);
  }

  /// Verifies an 8-byte write ack packet from the controller.
  static bool verifyWriteAck(
    List<int> packet, {
    int? expectedAddress,
    int? expectedValue,
  }) {
    if (packet.length < 8) return false;
    if (packet[0] != 0xAA) return false;
    if (!CrcCalculator.verifyCRC(packet, 8)) return false;
    if (expectedAddress != null && packet[2] != (expectedAddress & 0xFF)) {
      return false;
    }
    if (expectedValue != null) {
      final value = packet[4] | (packet[5] << 8);
      if (value != (expectedValue & 0xFFFF)) return false;
    }
    return true;
  }
}
