import 'dart:typed_data';

int _readUint16(List<int> raw, int offset) =>
    raw[offset] | (raw[offset + 1] << 8);

int _readInt16(List<int> raw, int offset) {
  final value = _readUint16(raw, offset);
  return value > 0x7FFF ? value - 0x10000 : value;
}

int _readInt8(List<int> raw, int offset) {
  final value = raw[offset] & 0xFF;
  return value > 0x7F ? value - 0x100 : value;
}

int _readUint32(List<int> raw, int offset) =>
    raw[offset] |
    (raw[offset + 1] << 8) |
    (raw[offset + 2] << 16) |
    (raw[offset + 3] << 24);

void _writeUint16(List<int> raw, int offset, int value) {
  raw[offset] = value & 0xFF;
  raw[offset + 1] = (value >> 8) & 0xFF;
}

void _writeInt16(List<int> raw, int offset, int value) {
  final uval = value < 0 ? (value + 0x10000) & 0xFFFF : value & 0xFFFF;
  _writeUint16(raw, offset, uval);
}

void _writeInt8(List<int> raw, int offset, int value) {
  raw[offset] = (value < 0 ? (value + 0x100) : value) & 0xFF;
}

void _writeUint32(List<int> raw, int offset, int value) {
  raw[offset] = value & 0xFF;
  raw[offset + 1] = (value >> 8) & 0xFF;
  raw[offset + 2] = (value >> 16) & 0xFF;
  raw[offset + 3] = (value >> 24) & 0xFF;
}

List<int> _copyBlock(List<int> raw) {
  if (raw.length != 12) {
    throw const FormatException(
        'FarDriver memory blocks must contain 12 bytes');
  }
  return List<int>.from(raw);
}

String _readAsciiString(List<int> raw, int offset, int length) {
  final chars = <int>[];
  for (var i = 0; i < length; i++) {
    final byte = raw[offset + i];
    if (byte >= 32 && byte <= 126) {
      chars.add(byte);
    }
  }
  return String.fromCharCodes(chars).trim();
}

void _writeAsciiString(List<int> raw, int offset, int length, String str) {
  final bytes = str.codeUnits;
  for (var i = 0; i < length; i++) {
    raw[offset + i] = i < bytes.length ? bytes[i] : 0;
  }
}

/// Base class for all FarDriver 12-byte parameter and telemetry blocks.
abstract class FarDriverMemoryBlock {
  final List<int> _raw;

  FarDriverMemoryBlock(List<int> raw) : _raw = _copyBlock(raw);

  int get address;
  List<int> toRaw() => List.unmodifiable(_raw);

  int readWord(int wordIndex) {
    if (wordIndex < 0 || wordIndex > 5) {
      throw RangeError.range(wordIndex, 0, 5);
    }
    return _readUint16(_raw, wordIndex * 2);
  }

  void writeWord(int wordIndex, int value) {
    if (wordIndex < 0 || wordIndex > 5) {
      throw RangeError.range(wordIndex, 0, 5);
    }
    _writeUint16(_raw, wordIndex * 2, value);
  }
}

// -----------------------------------------------------------------------------
// Block 0x00: Calibration & Zero Coeffs
// -----------------------------------------------------------------------------
class Addr00Block extends FarDriverMemoryBlock {
  Addr00Block._(super.raw);
  factory Addr00Block.fromRaw(List<int> raw) => Addr00Block._(raw);
  factory Addr00Block.empty() => Addr00Block._(List<int>.filled(12, 0));

  @override
  int get address => 0x00;

  int get volCoeff => _readInt16(_raw, 0);
  int get voltage2Coeff => _readInt16(_raw, 2);
  int get phaseACoeff => _readInt16(_raw, 4);
  int get lineCoeff => _readInt16(_raw, 6);
  int get phaseCCoeff => _readInt16(_raw, 8);
  int get saveNum => _readInt16(_raw, 10);
}

// -----------------------------------------------------------------------------
// Block 0x06: Motor Basic & Brake Config
// -----------------------------------------------------------------------------
class Addr06Block extends FarDriverMemoryBlock {
  Addr06Block._(super.raw);
  factory Addr06Block.fromRaw(List<int> raw) => Addr06Block._(raw);
  factory Addr06Block.empty() => Addr06Block._(List<int>.filled(12, 0));

  @override
  int get address => 0x06;

  int get antiTheftPulse => (_raw[0] >> 1) & 0x03;
  int get protocol485 => (_raw[0] >> 4) & 0x0F;
  int get morseCode => _raw[1] & 0x7F;
  int get speedKI => _raw[2];
  int get speedKP => _raw[3];
  int get throttleLowRaw => _raw[4];
  double get throttleLowVoltage => _raw[4] / 20.0;
  int get throttleHighRaw => _raw[5];
  double get throttleHighVoltage => _raw[5] / 20.0;
  int get faif => _readInt16(_raw, 6);
  int get curveTime => _readInt16(_raw, 8);
  int get brakeConfig => _raw[10] & 0x0F;
  int get tempSensor => (_raw[10] >> 4) & 0x07;
  bool get phaseExchange => ((_raw[10] >> 7) & 0x01) == 1;
  int get slowDown => _raw[11] & 0x07;
  bool get pc13RaceResponse => ((_raw[11] >> 3) & 0x01) == 1;
  bool get currAntiTheft => ((_raw[11] >> 4) & 0x01) == 1;
  int get parkConfig => (_raw[11] >> 5) & 0x03;
  int get motorDirection => (_raw[11] >> 7) & 0x01;

  Addr06Block withThrottleVoltages({double? low, double? high}) {
    final raw = List<int>.from(_raw);
    if (low != null) raw[4] = (low * 20.0).round().clamp(0, 255);
    if (high != null) raw[5] = (high * 20.0).round().clamp(0, 255);
    return Addr06Block._(raw);
  }
}

// -----------------------------------------------------------------------------
// Block 0x0C: Battery Limits & PID Start/Mid/Max
// -----------------------------------------------------------------------------
class Addr0CBlock extends FarDriverMemoryBlock {
  Addr0CBlock._(super.raw);
  factory Addr0CBlock.fromRaw(List<int> raw) => Addr0CBlock._(raw);
  factory Addr0CBlock.empty() => Addr0CBlock._(List<int>.filled(12, 0));

  @override
  int get address => 0x0C;

  int get phaseOffsetRaw => _readInt16(_raw, 0);
  double get phaseOffsetDegrees => _readInt16(_raw, 0) / 10.0;
  int get zeroBattCoeff => _readInt16(_raw, 2);
  int get fullBattCoeff => _readInt16(_raw, 4);
  int get startKI => _raw[6];
  int get midKI => _raw[7];
  int get maxKI => _raw[8];
  int get startKP => _raw[9];
  int get midKP => _raw[10];
  int get maxKP => _raw[11];
}

// -----------------------------------------------------------------------------
// Block 0x12: Motor Inductance & Max Speed
// -----------------------------------------------------------------------------
class Addr12Block extends FarDriverMemoryBlock {
  Addr12Block._(super.raw);
  factory Addr12Block.fromRaw(List<int> raw) => Addr12Block._(raw);
  factory Addr12Block.empty() => Addr12Block._(List<int>.filled(12, 0));

  @override
  int get address => 0x12;

  int get ld => _readInt16(_raw, 0);
  int get alarmDelay => _readUint16(_raw, 2);
  int get polePairs => _raw[4];
  int get maxSpeed => _readUint16(_raw, 6);
  int get ratedPower => _readUint16(_raw, 8);
  int get ratedVoltageRaw => _readUint16(_raw, 10);
  int get ratedVoltage => _readUint16(_raw, 10);
  double get ratedVoltageV => _readUint16(_raw, 10) / 10.0;

  Addr12Block withMaxSpeed(int value) {
    if (value < 0 || value > 0xFFFF) throw RangeError.range(value, 0, 0xFFFF);
    final raw = List<int>.from(_raw);
    _writeUint16(raw, 6, value);
    return Addr12Block._(raw);
  }
}

// -----------------------------------------------------------------------------
// Block 0x18: Currents & Throttle Response
// -----------------------------------------------------------------------------
class Addr18Block extends FarDriverMemoryBlock {
  Addr18Block._(super.raw);
  factory Addr18Block.fromRaw(List<int> raw) => Addr18Block._(raw);
  factory Addr18Block.empty() => Addr18Block._(List<int>.filled(12, 0));

  @override
  int get address => 0x18;

  int get ratedSpeed => _readUint16(_raw, 0);
  int get maxLineCurrentRaw => _readUint16(_raw, 2);
  double get maxLineCurrentAmps => _readUint16(_raw, 2) / 4.0;
  int get followConfig => _raw[4] & 0x03;
  int get throttleResponse => (_raw[4] >> 2) & 0x03;
  int get weakA => (_raw[4] >> 4) & 0x03;
  int get rxd => (_raw[4] >> 6) & 0x03;
  int get speedPulse => _raw[5] & 0x1F;
  int get gearConfig => (_raw[5] >> 5) & 0x07;
  int get lq => _readUint16(_raw, 6);
  int get batteryRatedCapacity => _readUint16(_raw, 8);
  int get intRes => _readUint16(_raw, 10);

  Addr18Block withThrottleResponse(int value) {
    if (value < 0 || value > 3) throw RangeError.range(value, 0, 3);
    final raw = List<int>.from(_raw);
    raw[4] = (raw[4] & 0xF3) | (value << 2);
    return Addr18Block._(raw);
  }

  Addr18Block withMaxLineCurrentAmps(double amps) {
    final raw = List<int>.from(_raw);
    final rawVal = (amps * 4.0).round().clamp(0, 0xFFFF);
    _writeUint16(raw, 2, rawVal);
    return Addr18Block._(raw);
  }
}

// -----------------------------------------------------------------------------
// Block 0x1E: Low Voltage & Feature Flags
// -----------------------------------------------------------------------------
class Addr1EBlock extends FarDriverMemoryBlock {
  Addr1EBlock._(super.raw);
  factory Addr1EBlock.fromRaw(List<int> raw) => Addr1EBlock._(raw);
  factory Addr1EBlock.empty() => Addr1EBlock._(List<int>.filled(12, 0));

  @override
  int get address => 0x1E;

  int get fwReRatio => _raw[0];
  int get lowVolProtectRaw => _readUint16(_raw, 2);
  double get lowVolProtectV => _readUint16(_raw, 2) / 10.0;
  String get customCode => _readAsciiString(_raw, 4, 2);
  bool get bcState => (_raw[6] & 0x01) == 1;
  bool get seatEnable => ((_raw[6] >> 1) & 0x01) == 1;
  bool get pEnable => ((_raw[6] >> 2) & 0x01) == 1;
  bool get autoBackPEnable => ((_raw[6] >> 3) & 0x01) == 1;
  bool get cruiseEnable => ((_raw[6] >> 4) & 0x01) == 1;
  bool get eabsEnable => ((_raw[6] >> 5) & 0x01) == 1;
  bool get pushEnable => ((_raw[6] >> 6) & 0x01) == 1;
  bool get forceAntiTheft => ((_raw[6] >> 7) & 0x01) == 1;
  bool get overSpeedAlarm => (_raw[7] & 0x01) == 1;
  bool get brakeStillPark => ((_raw[7] >> 1) & 0x01) == 1;
  bool get rememberGear => ((_raw[7] >> 2) & 0x01) == 1;
  bool get backEnable => ((_raw[7] >> 6) & 0x01) == 1;
  bool get relayDelay1S => ((_raw[7] >> 7) & 0x01) == 1;
  int get modelYear => _raw[8] + 2000;
  int get modelMonth => _raw[9];
  int get modelDay => _raw[10];
  int get timeHour => _raw[11];

  Addr1EBlock withLowVolProtectV(double volts) {
    final raw = List<int>.from(_raw);
    _writeUint16(raw, 2, (volts * 10.0).round().clamp(0, 0xFFFF));
    return Addr1EBlock._(raw);
  }
}

// -----------------------------------------------------------------------------
// Block 0x24: High Voltage, Boost Current & BackSpeed
// -----------------------------------------------------------------------------
class Addr24Block extends FarDriverMemoryBlock {
  Addr24Block._(super.raw);
  factory Addr24Block.fromRaw(List<int> raw) => Addr24Block._(raw);
  factory Addr24Block.empty() => Addr24Block._(List<int>.filled(12, 0));

  @override
  int get address => 0x24;

  int get timeMin => _raw[0];
  int get timeSecond => _raw[1];
  int get highVolProtectRaw => _readUint16(_raw, 2);
  double get highVolProtectV => _readUint16(_raw, 2) / 10.0;
  int get customMaxLineCurrRaw => _readUint16(_raw, 4);
  double get boostLineCurrA => _readUint16(_raw, 4) / 4.0;
  int get customMaxPhaseCurrRaw => _readUint16(_raw, 6);
  double get boostPhaseCurrA => _readUint16(_raw, 6) / 4.0;
  int get backSpeedRPM => _readUint16(_raw, 8);
  int get lowSpeedRPM => _readUint16(_raw, 10);

  Addr24Block withHighVolProtectV(double volts) {
    final raw = List<int>.from(_raw);
    _writeUint16(raw, 2, (volts * 10.0).round().clamp(0, 0xFFFF));
    return Addr24Block._(raw);
  }

  Addr24Block withBoostCurrents({double? lineA, double? phaseA}) {
    final raw = List<int>.from(_raw);
    if (lineA != null) {
      _writeUint16(raw, 4, (lineA * 4.0).round().clamp(0, 0xFFFF));
    }
    if (phaseA != null) {
      _writeUint16(raw, 6, (phaseA * 4.0).round().clamp(0, 0xFFFF));
    }
    return Addr24Block._(raw);
  }
}

// -----------------------------------------------------------------------------
// Block 0x2A: Phase Current, Acc/Dec Steps & FreeThrottle
// -----------------------------------------------------------------------------
class Addr2ABlock extends FarDriverMemoryBlock {
  Addr2ABlock._(super.raw);
  factory Addr2ABlock.fromRaw(List<int> raw) => Addr2ABlock._(raw);
  factory Addr2ABlock.empty() => Addr2ABlock._(List<int>.filled(12, 0));

  @override
  int get address => 0x2A;

  int get midSpeedRPM => _readUint16(_raw, 0);
  int get throttleDecStep => _readUint16(_raw, 2);
  int get freeThrottle => _raw[4];
  int get maxPhaseCurrRaw => _readUint16(_raw, 6);
  double get maxPhaseCurrA => _readUint16(_raw, 6) / 4.0;
  int get speedAnalogCoeff => _readUint16(_raw, 8);
  int get throttleAccStep => _readUint16(_raw, 10);

  Addr2ABlock withMaxPhaseCurrA(double amps) {
    final raw = List<int>.from(_raw);
    _writeUint16(raw, 6, (amps * 4.0).round().clamp(0, 0xFFFF));
    return Addr2ABlock._(raw);
  }

  Addr2ABlock withThrottleSteps({int? acc, int? dec}) {
    final raw = List<int>.from(_raw);
    if (dec != null) _writeUint16(raw, 2, dec.clamp(0, 0xFFFF));
    if (acc != null) _writeUint16(raw, 10, acc.clamp(0, 0xFFFF));
    return Addr2ABlock._(raw);
  }
}

// -----------------------------------------------------------------------------
// Block 0x30: Regen Currents & Gear Ratios
// -----------------------------------------------------------------------------
class Addr30Block extends FarDriverMemoryBlock {
  Addr30Block._(super.raw);
  factory Addr30Block.fromRaw(List<int> raw) => Addr30Block._(raw);
  factory Addr30Block.empty() => Addr30Block._(List<int>.filled(12, 0));

  @override
  int get address => 0x30;

  int get stopBackCurr => _readUint16(_raw, 0);
  int get maxBackCurr => _readUint16(_raw, 2);
  int get lowSpeedLineRatioRaw => _raw[4];
  double get lowSpeedLineRatioPct => (_raw[4] * 100.0 / 128.0);
  int get midSpeedLineRatioRaw => _raw[5];
  double get midSpeedLineRatioPct => (_raw[5] * 100.0 / 128.0);
  int get lowSpeedPhaseRatioRaw => _raw[6];
  double get lowSpeedPhaseRatioPct => (_raw[6] * 100.0 / 128.0);
  int get midSpeedPhaseRatioRaw => _raw[7];
  double get midSpeedPhaseRatioPct => (_raw[7] * 100.0 / 128.0);
  int get blockTimeSeconds => _readUint16(_raw, 8);
  int get spdPulseNum => _readUint16(_raw, 10);

  Addr30Block withRegenCurrents({int? stopA, int? maxA}) {
    final raw = List<int>.from(_raw);
    if (stopA != null) _writeUint16(raw, 0, stopA.clamp(0, 0xFFFF));
    if (maxA != null) _writeUint16(raw, 2, maxA.clamp(0, 0xFFFF));
    return Addr30Block._(raw);
  }
}

// -----------------------------------------------------------------------------
// Block 0x63: Production Hardware Limits
// -----------------------------------------------------------------------------
class Addr63Block extends FarDriverMemoryBlock {
  Addr63Block._(super.raw);
  factory Addr63Block.fromRaw(List<int> raw) => Addr63Block._(raw);
  factory Addr63Block.empty() => Addr63Block._(List<int>.filled(12, 0));

  @override
  int get address => 0x63;

  int get maxLineCurr2 => _readUint16(_raw, 0);
  int get maxPhaseCurr2 => _readUint16(_raw, 2);
  int get motorDia => _raw[4];
  int get tempCoeff => _readUint16(_raw, 6);
  double get prodMaxVol => _readUint16(_raw, 8) / 10.0;
  int get isMax => _readUint16(_raw, 10);
}

// -----------------------------------------------------------------------------
// Block 0x69: Hardware Pin Mappings
// -----------------------------------------------------------------------------
class Addr69Block extends FarDriverMemoryBlock {
  Addr69Block._(super.raw);
  factory Addr69Block.fromRaw(List<int> raw) => Addr69Block._(raw);
  factory Addr69Block.empty() => Addr69Block._(List<int>.filled(12, 0));

  @override
  int get address => 0x69;

  int get pausePin => _raw[0] & 0x0F;
  int get sideStandPin => (_raw[0] >> 4) & 0x0F;
  int get cruisePin => _raw[1] & 0x0F;
  int get boostPin => (_raw[1] >> 4) & 0x0F;
  int get lowSpeedPin => _raw[2] & 0x0F;
  int get highSpeedPin => (_raw[2] >> 4) & 0x0F;
  int get reversePin => _raw[3] & 0x0F;
  int get forwardPin => (_raw[3] >> 4) & 0x0F;
  int get switchVolPin => _raw[4] & 0x0F;
  int get seatPin => (_raw[4] >> 4) & 0x0F;
  int get antiTheftPin => _raw[5] & 0x0F;
  int get chargePin => (_raw[5] >> 4) & 0x0F;
  int get limitSpeedRPM => _readUint16(_raw, 6);
  int get distanceLSB => _readUint16(_raw, 8);
  int get paraIndex => _raw[10];
  int get specialCode => _raw[11];

  Addr69Block withPinMapping({
    int? pause,
    int? sideStand,
    int? cruise,
    int? boost,
    int? lowSpeed,
    int? highSpeed,
    int? reverse,
    int? forward,
  }) {
    final raw = List<int>.from(_raw);
    if (pause != null) raw[0] = (raw[0] & 0xF0) | (pause & 0x0F);
    if (sideStand != null) raw[0] = (raw[0] & 0x0F) | ((sideStand & 0x0F) << 4);
    if (cruise != null) raw[1] = (raw[1] & 0xF0) | (cruise & 0x0F);
    if (boost != null) raw[1] = (raw[1] & 0x0F) | ((boost & 0x0F) << 4);
    if (lowSpeed != null) raw[2] = (raw[2] & 0xF0) | (lowSpeed & 0x0F);
    if (highSpeed != null) raw[2] = (raw[2] & 0x0F) | ((highSpeed & 0x0F) << 4);
    if (reverse != null) raw[3] = (raw[3] & 0xF0) | (reverse & 0x0F);
    if (forward != null) raw[3] = (raw[3] & 0x0F) | ((forward & 0x0F) << 4);
    return Addr69Block._(raw);
  }
}

// -----------------------------------------------------------------------------
// Block 0x7C: Operating Hours, Speedo & Special Modes
// -----------------------------------------------------------------------------
class Addr7CBlock extends FarDriverMemoryBlock {
  Addr7CBlock._(super.raw);
  factory Addr7CBlock.fromRaw(List<int> raw) => Addr7CBlock._(raw);
  factory Addr7CBlock.empty() => Addr7CBlock._(List<int>.filled(12, 0));

  @override
  int get address => 0x7C;

  int get weakTime => (_raw[0] >> 1) & 0x07;
  int get quickDown => (_raw[0] >> 5) & 0x07;
  bool get fastRE => ((_raw[1] >> 2) & 0x01) == 1;
  bool get specialWeak => ((_raw[1] >> 3) & 0x01) == 1;
  bool get zeroSwitch => ((_raw[1] >> 4) & 0x01) == 1;
  bool get moe => ((_raw[1] >> 6) & 0x01) == 1;
  int get totalMinutes => _readUint32(_raw, 2);
  int get distanceMSB => _readUint16(_raw, 10);
}

// -----------------------------------------------------------------------------
// Block 0x82: Temperature Cutoffs & CAN Baud
// -----------------------------------------------------------------------------
class Addr82Block extends FarDriverMemoryBlock {
  Addr82Block._(super.raw);
  factory Addr82Block.fromRaw(List<int> raw) => Addr82Block._(raw);
  factory Addr82Block.empty() => Addr82Block._(List<int>.filled(12, 0));

  @override
  int get address => 0x82;

  double get brakeVoltage => _readUint16(_raw, 0) * 0.01;
  double get highVolRestoreV => _readUint16(_raw, 2) / 10.0;
  int get motorTempProtectC => _raw[4];
  int get motorTempRestoreC => _raw[5];
  int get mosTempProtectC => _raw[6];
  int get mosTempRestoreC => _raw[7];
  int get canConfig => _raw[8] & 0x3F;
  String get hardwareVersion => _readAsciiString(_raw, 9, 1);
  String get softwareVersionMajor => _readAsciiString(_raw, 10, 1);
  int get softwareVersionMinor => _raw[11];

  Addr82Block withTempCutoffs({
    int? motorProtect,
    int? motorRestore,
    int? mosProtect,
    int? mosRestore,
  }) {
    final raw = List<int>.from(_raw);
    if (motorProtect != null) raw[4] = motorProtect.clamp(0, 255);
    if (motorRestore != null) raw[5] = motorRestore.clamp(0, 255);
    if (mosProtect != null) raw[6] = mosProtect.clamp(0, 255);
    if (mosRestore != null) raw[7] = mosRestore.clamp(0, 255);
    return Addr82Block._(raw);
  }
}

// -----------------------------------------------------------------------------
// Block 0x88: Speed Curve Ratios (500 .. 5500 RPM)
// -----------------------------------------------------------------------------
class Addr88Block extends FarDriverMemoryBlock {
  Addr88Block._(super.raw);
  factory Addr88Block.fromRaw(List<int> raw) => Addr88Block._(raw);
  factory Addr88Block.empty() =>
      Addr88Block._(List<int>.filled(12, 100)); // Default 100%

  @override
  int get address => 0x88;

  int get ratioMin => _raw[0];
  int get ratio500 => _raw[1];
  int get ratio1000 => _raw[2];
  int get ratio1500 => _raw[3];
  int get ratio2000 => _raw[4];
  int get ratio2500 => _raw[5];
  int get ratio3000 => _raw[6];
  int get ratio3500 => _raw[7];
  int get ratio4000 => _raw[8];
  int get ratio4500 => _raw[9];
  int get ratio5000 => _raw[10];
  int get ratio5500 => _raw[11];

  List<int> get ratios => List.unmodifiable(_raw);

  Addr88Block withRatios(List<int> newRatios) {
    final raw = List<int>.from(_raw);
    for (var i = 0; i < 12 && i < newRatios.length; i++) {
      raw[i] = newRatios[i].clamp(0, 100);
    }
    return Addr88Block._(raw);
  }
}

// -----------------------------------------------------------------------------
// Block 0x8E: Speed Curve Part 2 (6000 .. 9000 RPM) & Regen Part 1
// -----------------------------------------------------------------------------
class Addr8EBlock extends FarDriverMemoryBlock {
  Addr8EBlock._(super.raw);
  factory Addr8EBlock.fromRaw(List<int> raw) => Addr8EBlock._(raw);
  factory Addr8EBlock.empty() => Addr8EBlock._(List<int>.filled(12, 0));

  @override
  int get address => 0x8E;

  int get ratio6000 => _raw[0];
  int get ratio6500 => _raw[1];
  int get ratio7000 => _raw[2];
  int get ratio7500 => _raw[3];
  int get ratio8000 => _raw[4];
  int get ratio8500 => _raw[5];
  int get ratio9000 => _raw[6];
  int get ratioMax => _raw[7];

  int get nratio0 => _readInt8(_raw, 8);
  int get nratio1 => _readInt8(_raw, 9);
  int get nratio2 => _readInt8(_raw, 10);
  int get nratio3 => _readInt8(_raw, 11);

  Addr8EBlock withUpperSpeedRatios(List<int> upperRatios) {
    final raw = List<int>.from(_raw);
    for (var i = 0; i < 8 && i < upperRatios.length; i++) {
      raw[i] = upperRatios[i].clamp(0, 100);
    }
    return Addr8EBlock._(raw);
  }

  Addr8EBlock withRegenRatios(List<int> regen) {
    final raw = List<int>.from(_raw);
    for (var i = 0; i < 4 && i < regen.length; i++) {
      _writeInt8(raw, 8 + i, regen[i].clamp(-100, 100));
    }
    return Addr8EBlock._(raw);
  }
}

// -----------------------------------------------------------------------------
// Block 0x94: Regen Curve Part 2 (nratio 4 .. 15)
// -----------------------------------------------------------------------------
class Addr94Block extends FarDriverMemoryBlock {
  Addr94Block._(super.raw);
  factory Addr94Block.fromRaw(List<int> raw) => Addr94Block._(raw);
  factory Addr94Block.empty() => Addr94Block._(List<int>.filled(12, 0));

  @override
  int get address => 0x94;

  List<int> get regenRatios =>
      List.unmodifiable(List.generate(12, (index) => _readInt8(_raw, index)));

  Addr94Block withRegenRatios(List<int> ratios) {
    final raw = List<int>.from(_raw);
    for (var i = 0; i < 12 && i < ratios.length; i++) {
      _writeInt8(raw, i, ratios[i].clamp(-100, 100));
    }
    return Addr94Block._(raw);
  }
}

// -----------------------------------------------------------------------------
// Block 0x9A: Regen Part 3, AN & LM PID Regler
// -----------------------------------------------------------------------------
class Addr9ABlock extends FarDriverMemoryBlock {
  Addr9ABlock._(super.raw);
  factory Addr9ABlock.fromRaw(List<int> raw) => Addr9ABlock._(raw);
  factory Addr9ABlock.empty() => Addr9ABlock._(List<int>.filled(12, 0));

  @override
  int get address => 0x9A;

  int get nratio16 => _readInt8(_raw, 0);
  int get nratio17 => _readInt8(_raw, 1);
  int get nratio18 => _readInt8(_raw, 2);
  int get nratio19 => _readInt8(_raw, 3);
  int get anWaveType => _raw[4] & 0x0F;
  bool get relayOut => ((_raw[4] >> 5) & 0x01) == 1;
  int get emptySpeed => (_raw[4] >> 6) & 0x03;
  int get lmWaveInterval => _raw[5] & 0x1F;
  int get initVol => _readInt16(_raw, 6);
  int get stage1Curr => _readInt16(_raw, 8);
  int get volSelectRatio => _raw[10];

  Addr9ABlock withAnLm({int? an, int? lm}) {
    final raw = List<int>.from(_raw);
    if (an != null) raw[4] = (raw[4] & 0xF0) | (an & 0x0F);
    if (lm != null) raw[5] = (raw[5] & 0xE0) | (lm & 0x1F);
    return Addr9ABlock._(raw);
  }
}

// -----------------------------------------------------------------------------
// Block 0xA0: System Command & Model Name Part 1
// -----------------------------------------------------------------------------
class AddrA0Block extends FarDriverMemoryBlock {
  AddrA0Block._(super.raw);
  factory AddrA0Block.fromRaw(List<int> raw) => AddrA0Block._(raw);
  factory AddrA0Block.empty() => AddrA0Block._(List<int>.filled(12, 0));

  @override
  int get address => 0xA0;

  int get unkA0 => _raw[0];
  int get sysCmd => _raw[1];
  String get modelNamePart1 => _readAsciiString(_raw, 2, 10);
}

// -----------------------------------------------------------------------------
// Block 0xA6: Model Name Part 2 & Serial
// -----------------------------------------------------------------------------
class AddrA6Block extends FarDriverMemoryBlock {
  AddrA6Block._(super.raw);
  factory AddrA6Block.fromRaw(List<int> raw) => AddrA6Block._(raw);
  factory AddrA6Block.empty() => AddrA6Block._(List<int>.filled(12, 0));

  @override
  int get address => 0xA6;

  String get modelNamePart2 => _readAsciiString(_raw, 0, 10);
  int get serialWord => _readUint16(_raw, 10);
}

// -----------------------------------------------------------------------------
// Block 0xB8: Display Positions & CAN Baud
// -----------------------------------------------------------------------------
class AddrB8Block extends FarDriverMemoryBlock {
  AddrB8Block._(super.raw);
  factory AddrB8Block.fromRaw(List<int> raw) => AddrB8Block._(raw);
  factory AddrB8Block.empty() => AddrB8Block._(List<int>.filled(12, 0));

  @override
  int get address => 0xB8;

  int get pPosition => _raw[0] & 0x0F;
  int get bcPosition => (_raw[0] >> 4) & 0x0F;
  int get hbarPosition => _raw[1] & 0x0F;
  int get fdPosition => (_raw[1] >> 4) & 0x0F;
  int get pulse => _raw[4];
  int get sqh => _raw[5];
  int get onelineCurrCoeff => _readUint16(_raw, 6);
  int get backPTimeSeconds => (_raw[8] & 0x1F) * 2;
  int get releaseToSeatSeconds => (_raw[8] >> 5) & 0x07;
  int get canBaud => _raw[9] & 0x03;
  int get stage1Soc => _raw[10];
  int get stage2Soc => _raw[11];
}

// -----------------------------------------------------------------------------
// Block 0xBE: Boost Timers & Low Voltage Way
// -----------------------------------------------------------------------------
class AddrBEBlock extends FarDriverMemoryBlock {
  AddrBEBlock._(super.raw);
  factory AddrBEBlock.fromRaw(List<int> raw) => AddrBEBlock._(raw);
  factory AddrBEBlock.empty() => AddrBEBlock._(List<int>.filled(12, 0));

  @override
  int get address => 0xBE;

  int get lowVolWay => _raw[0];
  int get accCoeff => (_raw[1] >> 4) & 0x0F;
  int get boostTimeSeconds => (_readUint16(_raw, 2) / 500.0).round();
  int get boostReleaseSeconds => (_readUint16(_raw, 4) / 500.0).round();
  int get parkTimeSeconds => (_readUint16(_raw, 6) / 500.0).round();
  int get reverseTimeSeconds => _raw[8] & 0x3F;
  int get torqueCoeff => _readUint16(_raw, 10);

  AddrBEBlock withBoostTimes({int? timeS, int? releaseS}) {
    final raw = List<int>.from(_raw);
    if (timeS != null) {
      _writeUint16(raw, 2, (timeS * 500).clamp(0, 0xFFFF));
    }
    if (releaseS != null) {
      _writeUint16(raw, 4, (releaseS * 500).clamp(0, 0xFFFF));
    }
    return AddrBEBlock._(raw);
  }
}

// -----------------------------------------------------------------------------
// Block 0xC4: Throttle Learning & Advanced Flags
// -----------------------------------------------------------------------------
class AddrC4Block extends FarDriverMemoryBlock {
  AddrC4Block._(super.raw);
  factory AddrC4Block.fromRaw(List<int> raw) => AddrC4Block._(raw);
  factory AddrC4Block.empty() => AddrC4Block._(List<int>.filled(12, 0));

  @override
  int get address => 0xC4;

  int get learnVolLow => _raw[1];
  int get learnVolHigh => _raw[3];
  int get slowDownRpm => _readUint16(_raw, 4);
  int get startIs => _readUint16(_raw, 6);
  int get throttleInsert => _readUint16(_raw, 8);
  int get exitFollowSpeed => _raw[10];
  int get reCurrRatio => _raw[11];
}

// -----------------------------------------------------------------------------
// Block 0xCA: Speed Limits, Modes & Battery Signal
// -----------------------------------------------------------------------------
class AddrCABlock extends FarDriverMemoryBlock {
  AddrCABlock._(super.raw);
  factory AddrCABlock.fromRaw(List<int> raw) => AddrCABlock._(raw);
  factory AddrCABlock.empty() => AddrCABlock._(List<int>.filled(12, 0));

  @override
  int get address => 0xCA;

  int get angleLearn => _raw[0];
  int get speedLimitPin => _raw[1] & 0x0F;
  int get repairPin => (_raw[1] >> 4) & 0x0F;
  int get noCanCnt => _raw[2];
  int get spModeConfig => _raw[3] & 0x0F;
  int get temp70 => (_raw[3] >> 4) & 0x03;
  bool get pushRE => ((_raw[3] >> 6) & 0x01) == 1;
  bool get throttleLost => ((_raw[3] >> 7) & 0x01) == 1;
  int get learnThrottle => _raw[4];
  int get speedLowCap => _raw[5];
  int get midSpeedCap => _raw[6];
  int get speedLimitByCap => _raw[7];
  int get minSpeedCapCoeff => _raw[8];
  int get parkCoeff => _raw[9] & 0x0F;
  int get battSignal => (_raw[9] >> 4) & 0x0F;
  int get reIsinAcc => _readUint16(_raw, 10);
}

// -----------------------------------------------------------------------------
// Block 0xD0: Wheel Dimensions & Speed Ratio
// -----------------------------------------------------------------------------
class AddrD0Block extends FarDriverMemoryBlock {
  AddrD0Block._(super.raw);
  factory AddrD0Block.fromRaw(List<int> raw) => AddrD0Block._(raw);
  factory AddrD0Block.empty() => AddrD0Block._(List<int>.filled(12, 0));

  @override
  int get address => 0xD0;

  int get data0 => _raw[0];
  int get data1 => _raw[1];
  int get bmqHall => _raw[2];
  int get avgPowerWhPerKm => _raw[3] * 4;
  int get wheelRatio => _raw[4];
  int get wheelRadiusInch => _raw[5];
  int get avgSpeedKph => _raw[6];
  int get wheelWidthMm => _raw[7];
  int get rateRatio => _readUint16(_raw, 8);
  int get idleStep => _raw[10] & 0x03;
  int get stopStep => (_raw[10] >> 2) & 0x03;
  int get byteOption => (_raw[10] >> 4) & 0x0F;
  int get specialFrame => _raw[11];

  AddrD0Block withWheelDimensions({
    int? radiusInch,
    int? widthMm,
    int? ratio,
    int? rateRatio,
  }) {
    final raw = List<int>.from(_raw);
    if (radiusInch != null) raw[5] = radiusInch.clamp(0, 255);
    if (widthMm != null) raw[7] = widthMm.clamp(0, 255);
    if (ratio != null) raw[4] = ratio.clamp(0, 255);
    if (rateRatio != null) {
      _writeUint16(raw, 8, rateRatio.clamp(0, 0xFFFF));
    }
    return AddrD0Block._(raw);
  }
}

// =============================================================================
// Aggregated FarDriver Full Memory (Holds all 26 Parameter Blocks = 312 Bytes)
// =============================================================================
class FarDriverFullMemory {
  final Map<int, List<int>> _blocks;

  FarDriverFullMemory._(this._blocks);

  factory FarDriverFullMemory.empty() {
    final blocks = <int, List<int>>{};
    for (final addr in blockAddresses) {
      blocks[addr] = List<int>.filled(12, 0);
    }
    return FarDriverFullMemory._(blocks);
  }

  static const List<int> blockAddresses = [
    0x00,
    0x06,
    0x0C,
    0x12,
    0x18,
    0x1E,
    0x24,
    0x2A,
    0x30,
    0x63,
    0x69,
    0x7C,
    0x82,
    0x88,
    0x8E,
    0x94,
    0x9A,
    0xA0,
    0xA6,
    0xAC,
    0xB2,
    0xB8,
    0xBE,
    0xC4,
    0xCA,
    0xD0,
  ];

  factory FarDriverFullMemory.fromBlockMap(Map<int, List<int>> map) {
    final blocks = <int, List<int>>{};
    for (final addr in blockAddresses) {
      final data = map[addr];
      blocks[addr] =
          data != null ? List<int>.from(data) : List<int>.filled(12, 0);
    }
    return FarDriverFullMemory._(blocks);
  }

  List<int> getBlockRaw(int address) =>
      List.unmodifiable(_blocks[address] ?? List<int>.filled(12, 0));

  void setBlockRaw(int address, List<int> raw) {
    _blocks[address] = _copyBlock(raw);
  }

  Addr00Block get addr00 => Addr00Block.fromRaw(getBlockRaw(0x00));
  Addr06Block get addr06 => Addr06Block.fromRaw(getBlockRaw(0x06));
  Addr0CBlock get addr0C => Addr0CBlock.fromRaw(getBlockRaw(0x0C));
  Addr12Block get addr12 => Addr12Block.fromRaw(getBlockRaw(0x12));
  Addr18Block get addr18 => Addr18Block.fromRaw(getBlockRaw(0x18));
  Addr1EBlock get addr1E => Addr1EBlock.fromRaw(getBlockRaw(0x1E));
  Addr24Block get addr24 => Addr24Block.fromRaw(getBlockRaw(0x24));
  Addr2ABlock get addr2A => Addr2ABlock.fromRaw(getBlockRaw(0x2A));
  Addr30Block get addr30 => Addr30Block.fromRaw(getBlockRaw(0x30));
  Addr63Block get addr63 => Addr63Block.fromRaw(getBlockRaw(0x63));
  Addr69Block get addr69 => Addr69Block.fromRaw(getBlockRaw(0x69));
  Addr7CBlock get addr7C => Addr7CBlock.fromRaw(getBlockRaw(0x7C));
  Addr82Block get addr82 => Addr82Block.fromRaw(getBlockRaw(0x82));
  Addr88Block get addr88 => Addr88Block.fromRaw(getBlockRaw(0x88));
  Addr8EBlock get addr8E => Addr8EBlock.fromRaw(getBlockRaw(0x8E));
  Addr94Block get addr94 => Addr94Block.fromRaw(getBlockRaw(0x94));
  Addr9ABlock get addr9A => Addr9ABlock.fromRaw(getBlockRaw(0x9A));
  AddrA0Block get addrA0 => AddrA0Block.fromRaw(getBlockRaw(0xA0));
  AddrA6Block get addrA6 => AddrA6Block.fromRaw(getBlockRaw(0xA6));
  AddrB8Block get addrB8 => AddrB8Block.fromRaw(getBlockRaw(0xB8));
  AddrBEBlock get addrBE => AddrBEBlock.fromRaw(getBlockRaw(0xBE));
  AddrC4Block get addrC4 => AddrC4Block.fromRaw(getBlockRaw(0xC4));
  AddrCABlock get addrCA => AddrCABlock.fromRaw(getBlockRaw(0xCA));
  AddrD0Block get addrD0 => AddrD0Block.fromRaw(getBlockRaw(0xD0));

  String get fullModelName =>
      '${addrA0.modelNamePart1}${addrA6.modelNamePart2}'.trim();

  Map<int, List<int>> toMap() => Map.unmodifiable(
      {for (final k in _blocks.keys) k: List<int>.from(_blocks[k]!)});
}
