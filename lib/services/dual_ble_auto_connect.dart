import 'dart:async';
import 'package:arcdash/services/ant_bms_service.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/storage_service.dart';

/// Dual-BLE Auto-Remember: re-establishes the FarDriver controller and the
/// ANT BMS connections in the background when the app starts.
class DualBleAutoConnect {
  final StorageService _storage;
  final DongleService _controllerService;
  final AntBmsService _bmsService;

  bool _started = false;

  DualBleAutoConnect(this._storage, this._controllerService, this._bmsService);

  /// Kicks off background connects for both remembered devices. Safe to call
  /// multiple times; only the first invocation performs any work.
  void start() {
    if (_started) return;
    _started = true;

    final controllerId = _storage.loadLastControllerId();
    if (controllerId != null && controllerId.isNotEmpty) {
      unawaited(
        _controllerService.connectById(controllerId,
            name: 'Controller (gemerkt)'),
      );
    }

    final bmsId = _storage.loadLastBmsId();
    if (bmsId != null && bmsId.isNotEmpty) {
      unawaited(
        _bmsService.connectById(bmsId, name: 'ANT BMS (gemerkt)'),
      );
    }
  }
}
