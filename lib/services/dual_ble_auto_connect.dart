import 'dart:async';
import 'package:arcdash/models/bike_profile.dart';
import 'package:arcdash/services/ant_bms_service.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/storage_service.dart';

/// Dual-BLE Auto-Remember & Bike Selector Coordinator:
/// If an autoConnectBike is configured, automatically connects both Controller
/// and BMS assigned to that bike when the app starts.
class DualBleAutoConnect {
  final StorageService _storage;
  final DongleService _controllerService;
  final AntBmsService _bmsService;

  bool _started = false;

  DualBleAutoConnect(this._storage, this._controllerService, this._bmsService);

  /// Kicks off background connects for the configured bike or remembered devices.
  void start() {
    if (_started) return;
    _started = true;

    final autoBikeId = _storage.loadAutoConnectBikeId();
    if (autoBikeId != null && autoBikeId.isNotEmpty) {
      final bikes = _storage.loadBikes();
      BikeProfile? targetBike;
      for (final b in bikes) {
        if (b.id == autoBikeId) {
          targetBike = b;
          break;
        }
      }

      if (targetBike != null) {
        if (targetBike.controllerId.isNotEmpty) {
          unawaited(
            _controllerService.connectById(
              targetBike.controllerId,
              name: targetBike.controllerName,
            ),
          );
        }
        if (targetBike.bmsId.isNotEmpty) {
          unawaited(
            _bmsService.connectById(
              targetBike.bmsId,
              name: targetBike.bmsName,
            ),
          );
        }
        return;
      }
    }

    // Fallback: Legacy remembered devices if no explicit bike auto-connect was set
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
