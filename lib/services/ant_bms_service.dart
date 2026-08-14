import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/ble_transport.dart';
import 'package:arcdash/services/diagnostic_log.dart';
import 'package:arcdash/utils/packet_parser.dart';

// ANT BMS BLE service/characteristic UUIDs (same 0xFFE0/0xFFE1 UART style as
// the FarDriver dongle, but addressed as a separate parallel session).
const _bmsServiceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
const _bmsCharUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';

/// Advertised name prefix used by ANT BMS modules.
const antBmsNamePrefix = 'ANT';

/// Whether [name] or [remoteId] looks like an ANT BMS device.
bool isAntBmsName(String name, [String? remoteId]) {
  final cleanName = name.trimLeft().toUpperCase();
  if (cleanName.startsWith('ANT') || cleanName.contains('BMS')) return true;
  return false;
}

/// Transport for a parallel BLE session with an ANT BMS.
///
/// Runs completely independently of the FarDriver [DongleService] so the
/// controller connection and the battery monitor can be held simultaneously.
class AntBmsService implements BleTransport {
  final DiagnosticLog? diagnostics;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeChar;
  bool _writeWithoutResponse = true;
  StreamSubscription? _notifySubscription;
  StreamSubscription? _deviceStateSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  AntBmsService({this.diagnostics});

  final _connectionStateController =
      StreamController<DongleConnectionState>.broadcast();
  final _rawDataController = StreamController<List<int>>.broadcast();
  final _scanResultsController =
      StreamController<List<DiscoveredDongle>>.broadcast();

  @override
  Stream<DongleConnectionState> get connectionStateStream =>
      _connectionStateController.stream;
  @override
  Stream<List<int>> get rawDataStream => _rawDataController.stream;
  @override
  Stream<List<DiscoveredDongle>> get scanResultsStream =>
      _scanResultsController.stream;

  DongleConnectionState _state = DongleConnectionState.idle;
  @override
  DongleConnectionState get state => _state;

  BluetoothDevice? get connectedDevice => _connectedDevice;
  String? get connectedDeviceName => _connectedDevice?.platformName;
  String? get connectedDeviceId => _connectedDevice?.remoteId.str;

  void _setState(DongleConnectionState s) {
    _state = s;
    _connectionStateController.add(s);
  }

  @override
  Future<bool> isBluetoothOn() async {
    final adapterState = await FlutterBluePlus.adapterState.first;
    return adapterState == BluetoothAdapterState.on;
  }

  @override
  Future<void> startScan(
      {Duration timeout = const Duration(seconds: 10),
      bool showAllDevices = false}) async {
    _setState(DongleConnectionState.scanning);
    final results = <String, DiscoveredDongle>{};
    try {
      final sub = FlutterBluePlus.scanResults.listen((scanResults) {
        for (final r in scanResults) {
          final name = r.device.platformName;
          final advName = r.advertisementData.advName;
          final remoteId = r.device.remoteId.str;
          final displayName = name.isNotEmpty
              ? name
              : (advName.isNotEmpty
                  ? advName
                  : 'Unbenanntes BLE Gerät ($remoteId)');
          if (!showAllDevices && !isBikeHardwareName(displayName)) continue;
          results[remoteId] = DiscoveredDongle(
            device: r.device,
            name: displayName,
            rssi: r.rssi,
          );
          _scanResultsController.add(results.values.toList());
        }
      });
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: false,
      );
      await Future.delayed(timeout);
      await sub.cancel();
    } finally {
      await FlutterBluePlus.stopScan();
      if (_state == DongleConnectionState.scanning) {
        _setState(DongleConnectionState.idle);
      }
    }
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    if (_state == DongleConnectionState.scanning) {
      _setState(DongleConnectionState.idle);
    }
  }

  /// Connects to a discovered ANT BMS module.
  @override
  Future<bool> connect(DiscoveredDongle dongle) async {
    _setState(DongleConnectionState.connecting);
    diagnostics?.add(DiagnosticEventType.connect, details: {
      'status': 'bms_connecting',
      'name': dongle.name,
      'remoteId': dongle.device.remoteId.str,
      'rssi': dongle.rssi,
    });
    try {
      await dongle.device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );
      _connectedDevice = dongle.device;

      _deviceStateSubscription =
          dongle.device.connectionState.listen((fbpState) {
        if (fbpState == BluetoothConnectionState.disconnected) {
          _handleDisconnect();
        }
      });
      _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
        if (state == BluetoothAdapterState.off) _handleDisconnect();
      });

      final services = await dongle.device.discoverServices();
      final found = await _setupBmsService(services);
      if (!found) {
        await disconnect();
        _setState(DongleConnectionState.error);
        return false;
      }

      diagnostics?.add(DiagnosticEventType.connect, details: {
        'status': 'bms_connected',
        'name': dongle.name,
        'remoteId': dongle.device.remoteId.str,
      });
      _setState(DongleConnectionState.connected);
      return true;
    } catch (e) {
      diagnostics?.add(DiagnosticEventType.connect, details: {
        'status': 'bms_connect_error',
        'name': dongle.name,
        'remoteId': dongle.device.remoteId.str,
        'error': e.toString(),
      });
      await disconnect();
      _setState(DongleConnectionState.error);
      return false;
    }
  }

  /// Reconnects to a previously remembered BMS by its BLE remote id.
  ///
  /// Tries a direct connect first, then falls back to a short scan to rediscover
  /// the module (needed on iOS and for freshly booted Android stacks).
  Future<bool> connectById(String remoteId, {String? name}) async {
    if (_state == DongleConnectionState.connected &&
        connectedDeviceId == remoteId) {
      return true;
    }
    try {
      final device = BluetoothDevice.fromId(remoteId);
      if (await connect(DiscoveredDongle(
        device: device,
        name: name ?? remoteId,
        rssi: 0,
      ))) {
        return true;
      }
    } catch (_) {}
    final found = await _findByScan(remoteId);
    if (found == null) return false;
    return connect(found);
  }

  Future<DiscoveredDongle?> _findByScan(String remoteId) async {
    DiscoveredDongle? found;
    try {
      final sub = FlutterBluePlus.scanResults.listen((scanResults) {
        for (final r in scanResults) {
          if (r.device.remoteId.str == remoteId) {
            final name = r.device.platformName.isNotEmpty
                ? r.device.platformName
                : remoteId;
            found = DiscoveredDongle(
              device: r.device,
              name: name,
              rssi: r.rssi,
            );
          }
        }
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      await Future.delayed(const Duration(seconds: 8));
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    return found;
  }

  Future<bool> _setupBmsService(List<Object> services) async {
    // 1. Known service/characteristic lookup (FFE0 / FFE1)
    for (final svc in services) {
      final svcUuid = (svc as dynamic).uuid.toString().toLowerCase();
      if (!svcUuid.contains('ffe0')) continue;
      final chars = List<BluetoothCharacteristic>.from(
          (svc as dynamic).characteristics as List);
      for (final c in chars) {
        final cUuid = c.uuid.toString().toLowerCase();
        if (!cUuid.contains('ffe1') && !cUuid.contains('ffe2')) continue;
        final props = c.properties;
        final canWrite = props.write || props.writeWithoutResponse;

        _writeChar = c;
        _writeWithoutResponse = props.writeWithoutResponse;

        try {
          await c.setNotifyValue(true);
        } catch (e) {
          diagnostics?.add(DiagnosticEventType.connect, details: {
            'status': 'bms_notify_setup_exception',
            'uuid': c.uuid.toString(),
            'error': e.toString(),
          });
        }
        _notifySubscription = c.onValueReceived.listen((data) {
          if (data.isNotEmpty) {
            _rawDataController.add(List<int>.from(data));
          }
        });
        return true;
      }
    }

    // 2. Generic GATT fallback for any service/characteristic supporting notify + write
    for (final svc in services) {
      final chars = List<BluetoothCharacteristic>.from(
          (svc as dynamic).characteristics as List);
      for (final c in chars) {
        final props = c.properties;
        final supportsNotify = props.notify || props.indicate;
        final supportsWrite = props.write || props.writeWithoutResponse;

        if (supportsNotify && supportsWrite) {
          _writeChar = c;
          _writeWithoutResponse = props.writeWithoutResponse;

          try {
            await c.setNotifyValue(true);
          } catch (e) {
            diagnostics?.add(DiagnosticEventType.connect, details: {
              'status': 'bms_notify_setup_exception_fallback',
              'uuid': c.uuid.toString(),
              'error': e.toString(),
            });
          }
          _notifySubscription = c.onValueReceived.listen((data) {
            if (data.isNotEmpty) {
              _rawDataController.add(List<int>.from(data));
            }
          });
          return true;
        }
      }
    }
    return false;
  }

  @override
  Future<bool> write(List<int> data) async {
    if (_writeChar == null || _state != DongleConnectionState.connected) {
      return false;
    }
    try {
      await _writeChar!.write(data, withoutResponse: _writeWithoutResponse);
      diagnostics?.add(DiagnosticEventType.command, details: {
        'action': 'bms_frame_written',
        'length': data.length,
        'hex': PacketParser.toHexString(data),
      });
      return true;
    } catch (e) {
      diagnostics?.add(DiagnosticEventType.command, details: {
        'action': 'bms_write_failed',
        'error': e.toString(),
      });
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    await _deviceStateSubscription?.cancel();
    _deviceStateSubscription = null;
    await _adapterStateSubscription?.cancel();
    _adapterStateSubscription = null;

    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (_) {}
      _connectedDevice = null;
    }
    _writeChar = null;
    _writeWithoutResponse = true;
    _setState(DongleConnectionState.disconnected);
  }

  void _handleDisconnect() {
    _notifySubscription?.cancel();
    _notifySubscription = null;
    _adapterStateSubscription?.cancel();
    _adapterStateSubscription = null;
    _writeChar = null;
    _writeWithoutResponse = true;
    _connectedDevice = null;
    _setState(DongleConnectionState.disconnected);
  }

  @override
  void dispose() {
    _notifySubscription?.cancel();
    _deviceStateSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    _connectionStateController.close();
    _rawDataController.close();
    _scanResultsController.close();
  }
}
