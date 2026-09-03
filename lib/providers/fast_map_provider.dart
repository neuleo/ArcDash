import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/tuning_provider.dart';
import 'package:arcdash/services/bluetooth_service.dart'
    show DongleConnectionState;

class FastMapState {
  final String activeRamMap;
  final String? tunedProfileName;
  final String stockProfileName;
  final bool autoApplyOnConnect;
  final bool isApplying;
  final String? statusMessage;
  final String? lastError;

  const FastMapState({
    this.activeRamMap = 'Stock Street Legal',
    this.tunedProfileName,
    this.stockProfileName = 'Stock Street Legal',
    this.autoApplyOnConnect = false,
    this.isApplying = false,
    this.statusMessage,
    this.lastError,
  });

  FastMapState copyWith({
    String? activeRamMap,
    String? tunedProfileName,
    String? stockProfileName,
    bool? autoApplyOnConnect,
    bool? isApplying,
    String? statusMessage,
    String? lastError,
  }) =>
      FastMapState(
        activeRamMap: activeRamMap ?? this.activeRamMap,
        tunedProfileName: tunedProfileName ?? this.tunedProfileName,
        stockProfileName: stockProfileName ?? this.stockProfileName,
        autoApplyOnConnect: autoApplyOnConnect ?? this.autoApplyOnConnect,
        isApplying: isApplying ?? this.isApplying,
        statusMessage: statusMessage,
        lastError: lastError,
      );
}

class FastMapNotifier extends StateNotifier<FastMapState> {
  final Ref _ref;
  StreamSubscription<DongleConnectionState>? _connSub;
  bool _hasAutoAppliedThisSession = false;

  FastMapNotifier(this._ref) : super(const FastMapState()) {
    _loadConfig();
    _initConnectionListener();
  }

  void _loadConfig() {
    try {
      final storage = _ref.read(storageServiceProvider);
      final tuned = storage.loadFastMapTunedProfile();
      final stock = storage.loadFastMapStockProfile();
      final auto = storage.loadFastMapAutoApply();
      state = state.copyWith(
        tunedProfileName: tuned,
        stockProfileName: stock,
        autoApplyOnConnect: auto,
      );
    } catch (_) {}
  }

  void _initConnectionListener() {
    try {
      final ble = _ref.read(bluetoothServiceProvider);
      _connSub = ble.connectionStateStream.listen((cs) {
        if (cs == DongleConnectionState.connected) {
          if (state.autoApplyOnConnect && !_hasAutoAppliedThisSession) {
            _hasAutoAppliedThisSession = true;
            // Allow controller communication to settle before sending write
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) {
                applyTunedProfile();
              }
            });
          }
        } else if (cs == DongleConnectionState.disconnected) {
          _hasAutoAppliedThisSession = false;
          state = state.copyWith(
            activeRamMap: 'Stock Street Legal (Werks-Boot)',
            statusMessage:
                'Bike getrennt — Controller startet nach Boot im Flash-Zustand',
          );
        }
      });
    } catch (_) {}
  }

  Future<bool> applyStockProfile() async {
    if (state.isApplying) return false;
    state =
        state.copyWith(isApplying: true, statusMessage: null, lastError: null);

    final tuningNotifier = _ref.read(tuningProvider.notifier);
    final tuningState = _ref.read(tuningProvider);

    TuningProfile? profile;
    for (final p in tuningState.savedProfiles) {
      if (p.name == state.stockProfileName) {
        profile = p;
        break;
      }
    }
    profile ??= TuningProfile.stockStreetLegal();

    tuningNotifier.loadPreset(profile);
    final success = await tuningNotifier.applyProfile(saveToFlash: false);

    if (success) {
      state = state.copyWith(
        isApplying: false,
        activeRamMap: profile.name,
        statusMessage:
            '${profile.name} erfolgreich in RAM geschrieben (45 km/h)!',
        lastError: null,
      );
      return true;
    } else {
      state = state.copyWith(
        isApplying: false,
        lastError: tuningState.lastError ?? 'Schreiben in RAM fehlgeschlagen.',
      );
      return false;
    }
  }

  Future<bool> applyTunedProfile() async {
    if (state.isApplying) return false;
    state =
        state.copyWith(isApplying: true, statusMessage: null, lastError: null);

    final tuningNotifier = _ref.read(tuningProvider.notifier);
    final tuningState = _ref.read(tuningProvider);

    // Profile must be explicitly present in savedProfiles or factory L1E preset
    TuningProfile? profile;
    final allAvailable = [
      ...TuningProfile.l1ePresets(),
      ...tuningState.savedProfiles,
    ];

    if (state.tunedProfileName != null) {
      for (final p in allAvailable) {
        if (p.name == state.tunedProfileName) {
          profile = p;
          break;
        }
      }
    }

    // Fallback: first non-stock custom profile, or first available
    profile ??= tuningState.savedProfiles.firstOrNull ??
        TuningProfile.l1ePresets().first;

    tuningNotifier.loadPreset(profile);
    final success = await tuningNotifier.applyProfile(saveToFlash: false);

    if (success) {
      state = state.copyWith(
        isApplying: false,
        activeRamMap: profile.name,
        statusMessage: '${profile.name} im RAM aktiv!',
        lastError: null,
      );
      return true;
    } else {
      state = state.copyWith(
        isApplying: false,
        lastError: tuningState.lastError ?? 'Schreiben in RAM fehlgeschlagen.',
      );
      return false;
    }
  }

  void setTunedProfileName(String name) {
    state = state.copyWith(tunedProfileName: name);
    try {
      _ref.read(storageServiceProvider).saveFastMapConfig(tunedProfile: name);
    } catch (_) {}
  }

  void setStockProfileName(String name) {
    state = state.copyWith(stockProfileName: name);
    try {
      _ref.read(storageServiceProvider).saveFastMapConfig(stockProfile: name);
    } catch (_) {}
  }

  void setAutoApplyOnConnect(bool value) {
    state = state.copyWith(autoApplyOnConnect: value);
    try {
      _ref
          .read(storageServiceProvider)
          .saveFastMapConfig(autoApplyOnConnect: value);
    } catch (_) {}
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }
}

final fastMapProvider =
    StateNotifierProvider<FastMapNotifier, FastMapState>((ref) {
  return FastMapNotifier(ref);
});
