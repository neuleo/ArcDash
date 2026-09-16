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
        final bike = targetBike;
        // Sequentially connect controller first, settle, then connect BMS
        if (bike.controllerId.isNotEmpty) {
          unawaited(() async {
            await _controllerService.connectById(
              bike.controllerId,
              name: bike.controllerName,
            );
            await Future.delayed(const Duration(milliseconds: 800));
            if (bike.bmsId.isNotEmpty) {
              await _bmsService.connectById(
                bike.bmsId,
                name: bike.bmsName,
              );
            }
          }());
        } else if (bike.bmsId.isNotEmpty) {
          unawaited(
            _bmsService.connectById(
              bike.bmsId,
              name: bike.bmsName,
            ),
          );
        }
        return;
      }
    }

    // Fallback: Legacy remembered devices if no explicit bike auto-connect was set
    final controllerId = _storage.loadLastControllerId();
    final bmsId = _storage.loadLastBmsId();

    unawaited(() async {
      if (controllerId != null && controllerId.isNotEmpty) {
        await _controllerService.connectById(controllerId,
            name: 'Controller (gemerkt)');
        await Future.delayed(const Duration(milliseconds: 800));
      }
      if (bmsId != null && bmsId.isNotEmpty) {
        await _bmsService.connectById(bmsId, name: 'ANT BMS (gemerkt)');
      }
    }());
  }
}
