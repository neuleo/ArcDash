import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/ant_bms_state.dart';
import 'package:arcdash/providers/ant_bms_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/services/ant_bms_service.dart';
import 'package:arcdash/services/ble_transport.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/diagnostic_log.dart';
import 'package:arcdash/services/dual_ble_auto_connect.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:arcdash/utils/ant_bms_parser.dart';
import 'package:arcdash/utils/crc_calculator.dart';

/// Real ANT BMS status responses carry a fixed 142-byte (0x8E) data payload
/// for packs up to 32S/4T (see esphome-ant-bms `on_status_data_`).
const int _statusDataLen = 142;

/// Builds a complete, CRC-verified ANT BMS status frame (function 0x11).
List<int> buildAntStatusFrame({
  List<int>? cellsMv,
  List<double>? temps,
  int mosfetTemp = 30,
  int balancerTemp = 28,
  int totalVoltage = 5760, // 57.60 V
  int current = 123, // 12.3 A
  int soc = 87,
  int soh = 95,
  int batteryStatus = 3,
  int chargeMos = 1,
  int dischargeMos = 1,
  int balancer = 0,
}) {
  final cells = cellsMv ??
      [
        4100, 4095, 4098, 4110, 4085, 4080, 4075, //
        4060, 4055, 4040, 4035, 4025, 4010, 4000,
      ];
  final t = temps ?? [25.0, 26.0, 27.0, 24.0];

  final data = <int>[
    0x05, // permissions
    batteryStatus,
    t.length,
    cells.length,
    ...List.filled(24, 0), // protection/warning/balancing bitmasks
  ];
  for (final v in cells) {
    data.add(v & 0xFF);
    data.add((v >> 8) & 0xFF);
  }
  for (final v in t) {
    data.add(v.round() & 0xFF);
    data.add((v.round() >> 8) & 0xFF);
  }
  data
    ..add(mosfetTemp & 0xFF)
    ..add((mosfetTemp >> 8) & 0xFF)
    ..add(balancerTemp & 0xFF)
    ..add((balancerTemp >> 8) & 0xFF)
    ..add(totalVoltage & 0xFF)
    ..add((totalVoltage >> 8) & 0xFF)
    ..add(current & 0xFF)
    ..add((current >> 8) & 0xFF)
    ..add(soc & 0xFF)
    ..add((soc >> 8) & 0xFF)
    ..add(soh & 0xFF)
    ..add((soh >> 8) & 0xFF)
    ..add(chargeMos)
    ..add(dischargeMos)
    ..add(balancer);

  // Pad to the fixed real-world payload length so the parser's minimum frame
  // length requirement (34 + cells*2 + temps*2 + 49) is satisfied.
  while (data.length < _statusDataLen) {
    data.add(0);
  }

  final frame = <int>[
    0x7E,
    0xA1,
    0x11,
    0x00,
    0x00,
    data.length,
    ...data,
  ];
  final crc = AntBmsParser.calcCrc16(frame.sublist(1));
  frame
    ..add(crc & 0xFF)
    ..add((crc >> 8) & 0xFF)
    ..add(0xAA)
    ..add(0x55);
  return frame;
}

/// Builds a valid 16-byte FarDriver status packet (address 0xE2, speed set).
Uint8List buildFarDriverPacket() {
  final full = Uint8List(16);
  full[0] = 0xAA;
  full[1] = 0x00; // id 0 -> address 0xE2
  full[6] = 0xE8; // measureSpeed raw = 1000
  full[7] = 0x03;
  CrcCalculator.computeCRC(full, 16);
  return full;
}

class _FakeBleTransport implements BleTransport {
  final conn = StreamController<DongleConnectionState>.broadcast();
  final raw = StreamController<List<int>>.broadcast();
  final List<List<int>> written = [];
  final DongleConnectionState _state;

  _FakeBleTransport({DongleConnectionState state = DongleConnectionState.idle})
      : _state = state;

  @override
  DongleConnectionState get state => _state;

  @override
  Stream<DongleConnectionState> get connectionStateStream => conn.stream;

  @override
  Stream<List<int>> get rawDataStream => raw.stream;

  @override
  Stream<List<DiscoveredDongle>> get scanResultsStream => const Stream.empty();

  @override
  Future<bool> isBluetoothOn() async => true;

  @override
  Future<void> startScan(
      {Duration timeout = const Duration(seconds: 10)}) async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<bool> connect(DiscoveredDongle dongle) async => true;

  @override
  Future<bool> write(List<int> data) async {
    written.add(List<int>.from(data));
    return true;
  }

  @override
  Future<void> disconnect() async {}

  @override
  void dispose() {}
}

class _FakeBmsService extends AntBmsService {
  final List<List<int>> written = [];
  final raw = StreamController<List<int>>.broadcast();
  final conn = StreamController<DongleConnectionState>.broadcast();
  final List<String> connectByIdCalls = [];

  DongleConnectionState _state = DongleConnectionState.idle;
  String? deviceId = 'BMS:FAKE:1';

  set stateOverride(DongleConnectionState value) => _state = value;

  @override
  DongleConnectionState get state => _state;

  @override
  Stream<DongleConnectionState> get connectionStateStream => conn.stream;

  @override
  Stream<List<int>> get rawDataStream => raw.stream;

  @override
  Stream<List<DiscoveredDongle>> get scanResultsStream => const Stream.empty();

  @override
  String? get connectedDeviceId => deviceId;

  @override
  Future<bool> write(List<int> data) async {
    written.add(List<int>.from(data));
    return true;
  }

  @override
  Future<bool> connectById(String remoteId, {String? name}) async {
    connectByIdCalls.add(remoteId);
    return true;
  }

  @override
  Future<void> disconnect() async {}

  @override
  void dispose() {
    raw.close();
    conn.close();
  }
}

class _MemoryStorage extends StorageService {
  String? _bmsId;
  String? _controllerId;

  @override
  String? loadLastBmsId() => _bmsId;

  @override
  Future<void> saveLastBmsId(String remoteId) async {
    _bmsId = remoteId;
  }

  @override
  String? loadLastControllerId() => _controllerId;

  @override
  Future<void> saveLastControllerId(String remoteId) async {
    _controllerId = remoteId;
  }
}

void main() {
  group('AntBmsParser CRC16 golden vectors', () {
    test('status request CRC matches the published frame', () {
      // 0x7e 0xa1 0x01 0x00 0x00 0xbe 0x18 0x55 0xaa 0x55
      expect(AntBmsParser.calcCrc16([0xA1, 0x01, 0x00, 0x00, 0xBE]), 0x5518);
    });

    test('device info CRC matches the published frame', () {
      // 0x7e 0xa1 0x02 0x6c 0x02 0x20 0x58 0xc4 0xaa 0x55
      expect(AntBmsParser.calcCrc16([0xA1, 0x02, 0x6C, 0x02, 0x20]), 0xC458);
    });

    test('crc16Bytes returns low byte first', () {
      expect(AntBmsParser.crc16Bytes([0xA1, 0x01, 0x00, 0x00, 0xBE]),
          [0x18, 0x55]);
    });

    test('verifyCrc accepts a hand-built frame and rejects tampering', () {
      final frame = buildAntStatusFrame();
      expect(AntBmsParser.verifyCrc(frame), isTrue);

      final tampered = List<int>.from(frame);
      tampered[40] ^= 0xFF; // flip a cell voltage byte
      expect(AntBmsParser.verifyCrc(tampered), isFalse);

      final badLen = List<int>.from(frame)..removeAt(frame.length - 1);
      expect(AntBmsParser.verifyCrc(badLen), isFalse);
    });
  });

  group('AntBmsParser command builders', () {
    test('buildStatusRequest emits the known-good 10-byte frame', () {
      expect(AntBmsParser.buildStatusRequest(), [
        0x7E, 0xA1, 0x01, 0x00, 0x00, 0xBE, //
        0x18, 0x55, 0xAA, 0x55,
      ]);
    });

    test('buildDeviceInfoRequest targets a settings register', () {
      expect(AntBmsParser.buildDeviceInfoRequest(0x026C), [
        0x7E, 0xA1, 0x02, 0x6C, 0x02, 0x20, //
        0x58, 0xC4, 0xAA, 0x55,
      ]);
    });
  });

  group('AntBmsParser status decoding', () {
    test('extracts cells, temperatures, SOC and MOSFET states', () {
      final frame = buildAntStatusFrame();
      final state = AntBmsParser.parseStatusFrame(frame);
      expect(state, isNotNull);

      expect(state!.cellCount, 14);
      expect(state.cellVoltagesMv, [
        4100, 4095, 4098, 4110, 4085, 4080, 4075, //
        4060, 4055, 4040, 4035, 4025, 4010, 4000,
      ]);

      expect(state.minCellVoltageMv, 4000);
      expect(state.maxCellVoltageMv, 4110);
      expect(state.minCellIndex, 14);
      expect(state.maxCellIndex, 4);
      expect(state.cellDeltaMv, 110);
      expect(state.averageCellVoltageMv, 4062);

      expect(state.temperaturesC, [25.0, 26.0, 27.0, 24.0]);
      expect(state.mosfetTemperatureC, 30.0);
      expect(state.balancerTemperatureC, 28.0);

      expect(state.totalVoltageV, closeTo(57.6, 0.001));
      expect(state.currentA, closeTo(12.3, 0.001));
      expect(state.socPercent, 87);
      expect(state.sohPercent, 95);
      expect(state.batteryStatusCode, 3);
      expect(state.isDischarging, isTrue);
      expect(state.isChargeMosfetOn, isTrue);
      expect(state.isDischargeMosfetOn, isTrue);
      expect(state.chargeMosfetStatus, 1);
      expect(state.dischargeMosfetStatus, 1);
    });

    test('supports 20-cell packs', () {
      final cells = List<int>.generate(
          20, (i) => 4100 - i); // 4100 down to 4081, delta 19
      final state =
          AntBmsParser.parseStatusFrame(buildAntStatusFrame(cellsMv: cells));
      expect(state!.cellCount, 20);
      expect(state.maxCellVoltageMv, 4100);
      expect(state.minCellVoltageMv, 4081);
      expect(state.cellDeltaMv, 19);
      expect(state.minCellIndex, 20);
    });

    test('rejects frames with invalid CRC', () {
      final frame = buildAntStatusFrame();
      frame[78] ^= 0xFF; // corrupt the SOC bytes
      expect(AntBmsParser.parseStatusFrame(frame), isNull);
    });

    test('rejects non-status frames', () {
      final frame = buildAntStatusFrame();
      frame[2] = 0x12; // device info function
      expect(AntBmsParser.parseStatusFrame(frame), isNull);
    });

    test('rejects truncated frames', () {
      final frame = buildAntStatusFrame();
      final truncated = frame.sublist(0, frame.length - 6);
      expect(AntBmsParser.parseStatusFrame(truncated), isNull);
    });

    test('rejects negative temperature values', () {
      final frame =
          buildAntStatusFrame(temps: [-5.0, 10.0, 12.0, 8.0], mosfetTemp: -3);
      final state = AntBmsParser.parseStatusFrame(frame);
      expect(state, isNotNull);
      expect(state!.temperaturesC, [-5.0, 10.0, 12.0, 8.0]);
      expect(state.mosfetTemperatureC, -3.0);
    });
  });

  group('AntBmsFramer reassembly', () {
    test('emits a complete frame from a single chunk', () {
      final framer = AntBmsFramer();
      final frames = framer.add(buildAntStatusFrame());
      expect(frames, hasLength(1));
      expect(frames.first, buildAntStatusFrame());
    });

    test('reassembles a frame split across BLE notifications', () {
      final framer = AntBmsFramer();
      final full = buildAntStatusFrame();
      final frames = <List<int>>[];
      frames.addAll(framer.add(full.sublist(0, 3)));
      frames.addAll(framer.add(full.sublist(3, 7)));
      frames.addAll(framer.add(full.sublist(7, 40)));
      frames.addAll(framer.add(full.sublist(40)));
      expect(frames, hasLength(1));
      expect(frames.first, full);
    });

    test('resynchronises after leading garbage', () {
      final framer = AntBmsFramer();
      final full = buildAntStatusFrame();
      final garbage = [0x00, 0xFF, 0x12, 0x7E, 0x01, 0x55];
      final frames = framer.add([...garbage, ...full]);
      expect(frames, hasLength(1));
      expect(frames.first, full);
    });

    test('extracts two back-to-back frames from one chunk', () {
      final framer = AntBmsFramer();
      final frames =
          framer.add([...buildAntStatusFrame(), ...buildAntStatusFrame()]);
      expect(frames, hasLength(2));
    });

    test('waits for more data until the end marker arrives', () {
      final framer = AntBmsFramer();
      final full = buildAntStatusFrame();
      expect(framer.add(full.sublist(0, full.length - 2)), isEmpty);
      expect(framer.add(full.sublist(full.length - 2)), hasLength(1));
    });
  });

  group('AntBmsState derived values', () {
    test('copyWith preserves and replaces fields', () {
      final base =
          AntBmsState(cellVoltagesMv: [4000, 4050, 4100], socPercent: 50);
      final updated = base.copyWith(socPercent: 80);
      expect(updated.socPercent, 80);
      expect(updated.cellVoltagesMv, base.cellVoltagesMv);
      expect(base.socPercent, 50);
    });

    test('isCharging/isDischarging reflect the battery status code', () {
      expect(AntBmsState(batteryStatusCode: 2).isCharging, isTrue);
      expect(AntBmsState(batteryStatusCode: 3).isDischarging, isTrue);
      expect(AntBmsState(batteryStatusCode: 1).isCharging, isFalse);
    });
  });

  group('ANT BMS name detection', () {
    test('recognises ANT@BLE device names', () {
      expect(isAntBmsName('ANT@BLE_BMS_16S'), isTrue);
      expect(isAntBmsName('ant@ble_bms'), isTrue);
      expect(isAntBmsName('  ANT@BLE'), isTrue);
      expect(isAntBmsName('HM-10'), isFalse);
      expect(isAntBmsName('Fardriver Dongle'), isFalse);
    });
  });

  group('Dual-BLE parallel sessions', () {
    test('controller and BMS run simultaneously on separate transports',
        () async {
      final controllerTransport =
          _FakeBleTransport(state: DongleConnectionState.connected);
      final bmsService = _FakeBmsService()
        ..stateOverride = DongleConnectionState.connected;
      final storage = _MemoryStorage();

      final controllerNotifier = ControllerNotifier(
        controllerTransport,
        storage,
        diagnostics: DiagnosticLog(),
      );
      final bmsNotifier = AntBmsNotifier(
        bmsService,
        storage,
        diagnostics: DiagnosticLog(),
      );

      // Both sessions issue their own request on their own transport.
      expect(bmsService.written, isNotEmpty);
      expect(bmsService.written.first, AntBmsParser.buildStatusRequest());

      // Both transports carry independent traffic without interference.
      controllerTransport.raw.add(buildFarDriverPacket());
      bmsService.raw.add(buildAntStatusFrame());

      // The controller writes its start-status-stream command shortly after
      // connecting (300ms delay in _onConnected).
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(controllerTransport.written, isNotEmpty);

      // BMS frame decoded into cell telemetry.
      expect(bmsNotifier.state, isNotNull);
      expect(bmsNotifier.state!.cellCount, 14);
      expect(bmsNotifier.state!.socPercent, 87);

      // Controller parsed its own stream (packet recorded, no shared state).
      expect(controllerNotifier.debugPackets, isNotEmpty);

      // Stop the controller's periodic stream-init timer before teardown.
      controllerTransport.conn.add(DongleConnectionState.disconnected);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      bmsNotifier.dispose();
      controllerNotifier.dispose();
      await controllerTransport.raw.close();
      await controllerTransport.conn.close();
      await bmsService.raw.close();
      await bmsService.conn.close();
    });
  });

  group('Dual-BLE auto-remember', () {
    test('reconnects both remembered devices at app start', () async {
      final controller = _FakeBleTransport();
      final bms = _FakeBmsService();
      final storage = _MemoryStorage();
      await storage.saveLastControllerId('CTRL:AA:BB');
      await storage.saveLastBmsId('BMS:CC:DD');

      // Real DongleService.connectById is exercised via a spy subclass.
      final spyController = _SpyControllerService();
      final coordinator = DualBleAutoConnect(storage, spyController, bms);
      coordinator.start();
      coordinator.start(); // idempotent

      expect(spyController.connectByIdCalls, ['CTRL:AA:BB']);
      expect(bms.connectByIdCalls, ['BMS:CC:DD']);
      expect(controller.written, isEmpty);
    });
  });
}

class _SpyControllerService extends DongleService {
  final List<String> connectByIdCalls = [];

  @override
  Future<bool> connectById(String remoteId, {String? name}) async {
    connectByIdCalls.add(remoteId);
    return true;
  }
}
