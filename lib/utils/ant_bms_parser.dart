import 'dart:math' as math;
import 'package:arcdash/models/ant_bms_state.dart';

/// Decoder for the ANT BMS BLE protocol.
///
/// Frame layout (little-endian payloads):
/// ```text
/// [0x7E 0xA1] [function] [addr_lo addr_hi] [data_len] [data...] [crc_lo crc_hi] [0xAA 0x55]
/// ```
/// The Modbus CRC16 is computed over the bytes from `0xA1` (inclusive) up to
/// the last data byte. Total frame length is `6 + data_len + 4`.
class AntBmsParser {
  AntBmsParser._();

  static const int frameStart1 = 0x7E;
  static const int frameStart2 = 0xA1;
  static const int frameEnd1 = 0xAA;
  static const int frameEnd2 = 0x55;

  /// Command sent to request a full status snapshot.
  static const int commandStatus = 0x01;

  /// Command sent to read device info / settings registers.
  static const int commandDeviceInfo = 0x02;

  /// Function code of the status response frame.
  static const int frameTypeStatus = 0x11;

  /// Function code of the device info / settings response frame.
  static const int frameTypeDeviceInfo = 0x12;

  static const int _maxCells = 32;
  static const int _maxTemperatures = 4;

  /// Computes the Modbus CRC16 (poly 0xA001, init 0xFFFF, no final XOR)
  /// over all bytes of [data].
  static int calcCrc16(List<int> data) {
    var crc = 0xFFFF;
    for (final byte in data) {
      crc ^= byte & 0xFF;
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x0001) != 0) {
          crc = (crc >> 1) ^ 0xA001;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc & 0xFFFF;
  }

  /// Returns the 2-byte Modbus CRC16 of [data], low byte first.
  static List<int> crc16Bytes(List<int> data) {
    final crc = calcCrc16(data);
    return [crc & 0xFF, (crc >> 8) & 0xFF];
  }

  /// Verifies the trailing Modbus CRC16 of a complete [frame].
  static bool verifyCrc(List<int> frame) {
    final frameLen = frameLength(frame);
    if (frameLen == null || frame.length != frameLen) return false;
    final expected = calcCrc16(frame.sublist(1, frameLen - 4));
    final remoteLow = frame[frameLen - 4];
    final remoteHigh = frame[frameLen - 3];
    return expected == ((remoteHigh << 8) | remoteLow);
  }

  /// Computes the expected full length (`6 + data_len + 4`) of the frame whose
  /// header is at the start of [frame]. Returns null for malformed frames.
  static int? frameLength(List<int> frame) {
    if (frame.length < 10) return null;
    if (frame[0] != frameStart1 || frame[1] != frameStart2) return null;
    final dataLen = frame[5];
    final total = 6 + dataLen + 4;
    if (total > 200) return null;
    return total;
  }

  /// Builds a command frame for [function] targeting [address] with the given
  /// [value] as data length.
  static List<int> buildRequest({
    required int function,
    required int address,
    required int value,
  }) {
    final frame = <int>[
      frameStart1,
      frameStart2,
      function & 0xFF,
      address & 0xFF,
      (address >> 8) & 0xFF,
      value & 0xFF,
    ];
    final crc = calcCrc16(frame.sublist(1));
    frame.addAll([
      crc & 0xFF,
      (crc >> 8) & 0xFF,
      frameEnd1,
      frameEnd2,
    ]);
    return frame;
  }

  /// Builds the periodic status request frame
  /// (`0x7E 0xA1 0x01 0x00 0x00 0xBE ...`).
  static List<int> buildStatusRequest() =>
      buildRequest(function: commandStatus, address: 0x0000, value: 0xBE);

  /// Builds a device info request for a settings register.
  static List<int> buildDeviceInfoRequest(int address, {int length = 0x20}) =>
      buildRequest(
          function: commandDeviceInfo, address: address, value: length);

  /// Decodes a complete status frame (function `0x11`) into an
  /// [AntBmsState]. Returns null when the frame is not a valid status frame.
  static AntBmsState? parseStatusFrame(List<int> frame,
      {DateTime? capturedAt}) {
    final frameLen = frameLength(frame);
    if (frameLen == null ||
        frame.length != frameLen ||
        frame[2] != frameTypeStatus) {
      return null;
    }
    if (!verifyCrc(frame)) return null;

    final temperatureSensors = frame[8];
    final cells = frame[9];
    if (cells > _maxCells || temperatureSensors > _maxTemperatures) {
      return null;
    }

    var offset = cells * 2;

    final required = 34 + offset + temperatureSensors * 2 + 49;
    if (required > frameLen) return null;

    final cellVoltagesMv = <int>[];
    for (var i = 0; i < cells; i++) {
      cellVoltagesMv.add(_readU16(frame, 34 + i * 2));
    }

    final temperatures = <double>[];
    for (var i = 0; i < temperatureSensors; i++) {
      temperatures.add(_readI16(frame, 34 + offset + i * 2).toDouble());
    }

    offset += temperatureSensors * 2;

    final mosfetTemperature = _readI16(frame, 34 + offset);
    final balancerTemperature = _readI16(frame, 36 + offset);

    return AntBmsState(
      cellVoltagesMv: cellVoltagesMv,
      temperaturesC: temperatures,
      mosfetTemperatureC: mosfetTemperature.toDouble(),
      balancerTemperatureC: balancerTemperature.toDouble(),
      totalVoltageV: _readU16(frame, 38 + offset) * 0.01,
      currentA: _readI16(frame, 40 + offset) * 0.1,
      socPercent: _readU16(frame, 42 + offset),
      sohPercent: _readU16(frame, 44 + offset),
      batteryStatusCode: frame[7],
      chargeMosfetStatus: frame[46 + offset],
      dischargeMosfetStatus: frame[47 + offset],
      balancerStatus: frame[48 + offset],
      capturedAt: capturedAt ?? DateTime.now(),
    );
  }

  static int _readU16(List<int> data, int index) =>
      data[index] | (data[index + 1] << 8);

  static int _readI16(List<int> data, int index) =>
      _readU16(data, index).toSigned(16);
}

/// Incremental frame assembler for the ANT BMS byte stream.
///
/// BLE notifications may split or coalesce frames, so bytes are buffered and
/// complete frames (terminated by `0xAA 0x55`) are emitted as soon as the full
/// payload has arrived. The buffer is re-synchronised on the `0x7E 0xA1`
/// preamble.
class AntBmsFramer {
  final List<int> _buffer = [];

  static const int _maxBufferLength = 256;

  /// Feeds [chunk] into the assembler and returns all complete frames
  /// decoded from it.
  List<List<int>> add(List<int> chunk) {
    if (chunk.isNotEmpty) _buffer.addAll(chunk);
    final frames = <List<int>>[];

    while (true) {
      var syncIndex = -1;
      for (var i = 0; i + 1 < _buffer.length; i++) {
        if (_buffer[i] == AntBmsParser.frameStart1 &&
            _buffer[i + 1] == AntBmsParser.frameStart2) {
          syncIndex = i;
          break;
        }
      }
      if (syncIndex < 0) {
        _buffer.clear();
        break;
      }
      if (syncIndex > 0) _buffer.removeRange(0, syncIndex);

      final frameLen = AntBmsParser.frameLength(_buffer);
      if (frameLen == null) {
        // A header shorter than 10 bytes is simply an incomplete frame; keep
        // the bytes and wait for more notifications. Only discard a buffer
        // that is complete enough to be definitively malformed (e.g. an
        // oversized data length).
        if (_buffer.length < 10) break;
        _buffer.clear();
        break;
      }
      if (frameLen > _buffer.length) {
        if (_buffer.length > _maxBufferLength) _buffer.clear();
        break;
      }

      final frame = List<int>.from(_buffer.sublist(0, frameLen));
      _buffer.removeRange(0, frameLen);
      if (frame[frameLen - 2] == AntBmsParser.frameEnd1 &&
          frame[frameLen - 1] == AntBmsParser.frameEnd2) {
        frames.add(frame);
      }
    }
    return frames;
  }

  void reset() => _buffer.clear();
}

/// Human readable MOSFET / balancer switch states.
class AntBmsStatusLabels {
  AntBmsStatusLabels._();

  static const chargeMosfet = <int, String>{
    0x00: 'Aus',
    0x01: 'Ein',
    0x02: 'Überspannungsschutz',
    0x03: 'Überstromschutz',
    0x04: 'Akku voll',
    0x05: 'Gesamtüberspannung',
    0x06: 'Akku übertempiert',
    0x07: 'MOSFET übertempiert',
    0x08: 'Strom abnormal',
    0x09: 'Balancierleitung abgefallen',
    0x0A: 'Platine übertempiert',
    0x0C: 'Öffnen fehlgeschlagen',
    0x0D: 'Entlade-MOSFET defekt',
    0x0E: 'Warte',
    0x0F: 'Manuell ausgeschaltet',
    0x10: 'Zweistufige Überspannung',
    0x11: 'Untemperaturschutz',
    0x12: 'Spannungsdifferenz überschritten',
    0x14: 'Selbsttest-Fehler',
  };

  static const dischargeMosfet = <int, String>{
    0x00: 'Aus',
    0x01: 'Ein',
    0x02: 'Entladeschutz',
    0x03: 'Überstromschutz',
    0x04: 'Stromstufe überschritten',
    0x05: 'Gesamtunterspannung',
    0x06: 'Akku übertempiert',
    0x07: 'MOSFET übertempiert',
    0x08: 'Strom abnormal',
    0x09: 'Balancierleitung abgefallen',
    0x0A: 'Platine übertempiert',
    0x0B: 'Lade-MOSFET ein',
    0x0C: 'Kurzschlussschutz',
    0x0D: 'Entlade-MOSFET defekt',
    0x0E: 'Öffnen fehlgeschlagen',
    0x0F: 'Manuell ausgeschaltet',
    0x10: 'Zweistufige Unterspannung',
    0x11: 'Untemperaturschutz',
    0x12: 'Spannungsdifferenz überschritten',
    0x13: 'Selbsttest-Fehler',
  };

  static const batteryStatus = <int, String>{
    0x00: 'Unbekannt',
    0x01: 'Bereit',
    0x02: 'Lädt',
    0x03: 'Entlädt',
    0x04: 'Standby',
    0x05: 'Fehler',
  };

  static const balancer = <int, String>{
    0x00: 'Aus',
    0x01: 'Grenzausgleich',
    0x02: 'Lade-Druckausgleich',
    0x03: 'Übertemperatur-Ausgleich',
    0x04: 'Automatischer Ausgleich',
    0x0A: 'Platine übertempiert',
  };

  static String chargeMosfetLabel(int status) =>
      chargeMosfet[status] ?? 'Unbekannt ($status)';

  static String dischargeMosfetLabel(int status) =>
      dischargeMosfet[status] ?? 'Unbekannt ($status)';

  static String batteryStatusLabel(int status) =>
      batteryStatus[status] ?? 'Unbekannt ($status)';

  static String balancerLabel(int status) =>
      balancer[status] ?? 'Unbekannt ($status)';
}

/// Deviation severity of a single cell relative to the pack minimum.
enum CellDeviation {
  /// Within the balance tolerance (green).
  balanced,

  /// Moderate deviation (orange).
  elevated,

  /// Severe deviation (red).
  critical,
}

/// Classifies a cell's deviation (in mV) from the pack minimum.
CellDeviation cellDeviationForDelta(int deltaMv) {
  if (deltaMv <= 30) return CellDeviation.balanced;
  if (deltaMv <= 100) return CellDeviation.elevated;
  return CellDeviation.critical;
}

/// Scale helper used by the cell bar chart to keep all cells in one range.
class AntBmsChartScale {
  final int minMv;
  final int maxMv;

  const AntBmsChartScale({required this.minMv, required this.maxMv});

  double normalized(int valueMv) {
    final span = math.max(1, maxMv - minMv);
    return ((valueMv - minMv) / span).clamp(0.0, 1.0);
  }
}
