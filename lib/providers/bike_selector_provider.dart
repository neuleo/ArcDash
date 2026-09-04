import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/bike_profile.dart';
import 'package:arcdash/providers/ant_bms_provider.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/services/ant_bms_service.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/storage_service.dart';

class BikeSelectorState {
  final List<BikeProfile> bikes;
  final String? selectedBikeId;
  final String? autoConnectBikeId;
  final bool isConnecting;
  final String? connectingBikeId;
  final String? statusMessage;
  final String? lastError;

  const BikeSelectorState({
    this.bikes = const [],
    this.selectedBikeId,
    this.autoConnectBikeId,
    this.isConnecting = false,
    this.connectingBikeId,
    this.statusMessage,
    this.lastError,
  });

  BikeProfile? get selectedBike {
    if (selectedBikeId == null) return bikes.firstOrNull;
    for (final b in bikes) {
      if (b.id == selectedBikeId) return b;
    }
    return bikes.firstOrNull;
  }

  BikeProfile? get autoConnectBike {
    if (autoConnectBikeId == null) return null;
    for (final b in bikes) {
      if (b.id == autoConnectBikeId) return b;
    }
    return null;
  }

  BikeSelectorState copyWith({
    List<BikeProfile>? bikes,
    String? selectedBikeId,
    String? autoConnectBikeId,
    bool? isConnecting,
    String? connectingBikeId,
    String? statusMessage,
    String? lastError,
    bool clearSelectedBike = false,
    bool clearAutoConnect = false,
  }) {
    return BikeSelectorState(
      bikes: bikes ?? this.bikes,
      selectedBikeId:
          clearSelectedBike ? null : (selectedBikeId ?? this.selectedBikeId),
      autoConnectBikeId: clearAutoConnect
          ? null
          : (autoConnectBikeId ?? this.autoConnectBikeId),
      isConnecting: isConnecting ?? this.isConnecting,
      connectingBikeId: connectingBikeId ?? this.connectingBikeId,
      statusMessage: statusMessage,
      lastError: lastError,
    );
  }
}

class BikeSelectorNotifier extends StateNotifier<BikeSelectorState> {
  final Ref _ref;

  BikeSelectorNotifier(this._ref) : super(const BikeSelectorState()) {
    _loadBikes();
  }

  void _loadBikes() {
    try {
      final storage = _ref.read(storageServiceProvider);
      var bikes = storage.loadBikes();

      // Migration: If no bike exists yet, but we previously had remembered devices, create first bike automatically
      if (bikes.isEmpty) {
        final lastCtrl = storage.loadLastControllerId();
        if (lastCtrl != null && lastCtrl.isNotEmpty) {
          final lastBms = storage.loadLastBmsId() ?? '';
          final defaultBike = BikeProfile(
            id: 'bike_default_${DateTime.now().millisecondsSinceEpoch}',
            name: 'Mein E-Bike (Standard)',
            controllerId: lastCtrl,
            controllerName: 'FarDriver Controller',
            bmsId: lastBms,
            bmsName: lastBms.isNotEmpty ? 'ANT BMS' : '',
            createdAt: DateTime.now(),
          );
          storage.saveBike(defaultBike);
          bikes = [defaultBike];
          storage.saveSelectedBikeId(defaultBike.id);
          storage.saveAutoConnectBikeId(defaultBike.id);
        }
      }

      final selectedId = storage.loadSelectedBikeId() ?? bikes.firstOrNull?.id;
      final autoId = storage.loadAutoConnectBikeId();

      state = state.copyWith(
        bikes: bikes,
        selectedBikeId: selectedId,
        autoConnectBikeId: autoId,
      );
    } catch (_) {}
  }

  Future<void> saveBike(BikeProfile bike) async {
    final storage = _ref.read(storageServiceProvider);
    await storage.saveBike(bike);
    final bikes = storage.loadBikes();
    state = state.copyWith(
      bikes: bikes,
      selectedBikeId: bike.id,
      statusMessage: 'Bike "${bike.name}" gespeichert!',
    );
    await storage.saveSelectedBikeId(bike.id);
  }

  Future<void> deleteBike(String bikeId) async {
    final storage = _ref.read(storageServiceProvider);
    await storage.deleteBike(bikeId);
    final bikes = storage.loadBikes();
    final newSelected = storage.loadSelectedBikeId();
    final newAuto = storage.loadAutoConnectBikeId();
    state = state.copyWith(
      bikes: bikes,
      selectedBikeId: newSelected,
      autoConnectBikeId: newAuto,
      clearAutoConnect: newAuto == null,
      statusMessage: 'Bike gelöscht.',
    );
  }

  Future<void> selectBike(String bikeId) async {
    final storage = _ref.read(storageServiceProvider);
    await storage.saveSelectedBikeId(bikeId);
    state = state.copyWith(selectedBikeId: bikeId);
  }

  Future<void> setAutoConnectBike(String? bikeId) async {
    final storage = _ref.read(storageServiceProvider);
    await storage.saveAutoConnectBikeId(bikeId);
    state = state.copyWith(
      autoConnectBikeId: bikeId,
      clearAutoConnect: bikeId == null,
      statusMessage: bikeId != null
          ? 'Auto-Connect für dieses Bike aktiviert!'
          : 'Auto-Connect deaktiviert.',
    );
  }

  /// Connects both Controller and BMS assigned to [bike] simultaneously in the background.
  Future<bool> connectBike(BikeProfile bike) async {
    if (state.isConnecting) return false;
    state = state.copyWith(
      isConnecting: true,
      connectingBikeId: bike.id,
      statusMessage: 'Verbinde ${bike.name}...',
      lastError: null,
    );

    final storage = _ref.read(storageServiceProvider);
    final controllerService = _ref.read(bluetoothServiceProvider);
    final bmsService = _ref.read(antBmsServiceProvider);

    await storage.saveSelectedBikeId(bike.id);

    try {
      final futures = <Future<bool>>[];

      // 1. Controller connect
      if (bike.controllerId.isNotEmpty) {
        futures.add(controllerService.connectById(
          bike.controllerId,
          name: bike.controllerName.isNotEmpty
              ? bike.controllerName
              : 'Controller',
        ));
      }

      // 2. BMS connect (parallel)
      if (bike.bmsId.isNotEmpty) {
        futures.add(bmsService.connectById(
          bike.bmsId,
          name: bike.bmsName.isNotEmpty ? bike.bmsName : 'ANT BMS',
        ));
      }

      final results = await Future.wait(futures);
      final allSuccess = results.isNotEmpty && results.every((r) => r);

      state = state.copyWith(
        isConnecting: false,
        connectingBikeId: null,
        selectedBikeId: bike.id,
        statusMessage: allSuccess
            ? '${bike.name} erfolgreich gekoppelt (Controller & BMS aktiv)!'
            : 'Verbindung zu ${bike.name} hergestellt.',
        lastError:
            allSuccess ? null : 'Ein Gerät konnte nicht verbunden werden.',
      );
      return allSuccess;
    } catch (e) {
      state = state.copyWith(
        isConnecting: false,
        connectingBikeId: null,
        lastError: 'Verbindungsfehler: $e',
      );
      return false;
    }
  }

  /// Disconnects both devices belonging to currently connected session.
  Future<void> disconnectAll() async {
    final controllerService = _ref.read(bluetoothServiceProvider);
    final bmsService = _ref.read(antBmsServiceProvider);
    await controllerService.disconnect();
    await bmsService.disconnect();
    state = state.copyWith(statusMessage: 'Alle Bike-Verbindungen getrennt.');
  }
}

final bikeSelectorProvider =
    StateNotifierProvider<BikeSelectorNotifier, BikeSelectorState>((ref) {
  return BikeSelectorNotifier(ref);
});
