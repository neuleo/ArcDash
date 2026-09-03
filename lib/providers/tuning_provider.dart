import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/controller_identity.dart';
import 'package:arcdash/models/controller_state.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/services/heb_file_parser.dart';
import 'package:arcdash/services/protocol_service.dart';
import 'package:arcdash/services/stock_heb_restore.dart';
import 'package:arcdash/services/write_safety.dart';
import 'package:arcdash/utils/tuning_conversions.dart';

/// Identity of the connected controller. Parsed from live status.
final controllerIdentityProvider = Provider<ControllerIdentity>((ref) {
  return const ControllerIdentity();
});

/// Live fail-closed write authorization. A write is only allowed when the
/// controller is connected, standing still (speedKph == 0.0), the telemetry
/// stream is fresh and no fault is active.
final writeSafetyDecisionProvider = Provider<SafetyDecision>((ref) {
  final controller = ref.watch(controllerProvider);
  final connected = ref.watch(isConnectedProvider);
  final storage = ref.watch(storageServiceProvider);
  final identity = ref.watch(controllerIdentityProvider);
  return const SafetyEvaluator().evaluateState(
    now: DateTime.now(),
    connected: connected,
    identity: identity,
    backupAvailable: storage.hasStockBackup,
    speedKph: controller.speedKph,
    lastUpdate: controller.lastUpdate,
    hasFault: controller.hasAnyFault,
  );
});

class TuningState {
  final TuningProfile pendingProfile;
  final bool isApplying;
  final bool isRestoring;
  final bool isSavingToFlash;
  final String? lastError;
  final bool appliedSuccessfully;
  final bool lastAppliedWasFlash;
  final List<TuningProfile> savedProfiles;
  final bool expertModeEnabled;
  final String activeRamMap;

  const TuningState({
    required this.pendingProfile,
    this.isApplying = false,
    this.isRestoring = false,
    this.isSavingToFlash = false,
    this.lastError,
    this.appliedSuccessfully = false,
    this.lastAppliedWasFlash = false,
    this.savedProfiles = const [],
    this.expertModeEnabled = false,
    this.activeRamMap = 'Stock Street Legal',
  });

  TuningState copyWith({
    TuningProfile? pendingProfile,
    bool? isApplying,
    bool? isRestoring,
    bool? isSavingToFlash,
    String? lastError,
    bool? appliedSuccessfully,
    bool? lastAppliedWasFlash,
    List<TuningProfile>? savedProfiles,
    bool? expertModeEnabled,
    String? activeRamMap,
  }) =>
      TuningState(
        pendingProfile: pendingProfile ?? this.pendingProfile,
        isApplying: isApplying ?? this.isApplying,
        isRestoring: isRestoring ?? this.isRestoring,
        isSavingToFlash: isSavingToFlash ?? this.isSavingToFlash,
        lastError: lastError,
        appliedSuccessfully: appliedSuccessfully ?? this.appliedSuccessfully,
        lastAppliedWasFlash: lastAppliedWasFlash ?? this.lastAppliedWasFlash,
        savedProfiles: savedProfiles ?? this.savedProfiles,
        expertModeEnabled: expertModeEnabled ?? this.expertModeEnabled,
        activeRamMap: activeRamMap ?? this.activeRamMap,
      );
}

class TuningNotifier extends StateNotifier<TuningState> {
  final Ref _ref;
  bool _hasUserModified = false;

  TuningNotifier(this._ref)
      : super(TuningState(pendingProfile: TuningProfile.stockStreetLegal())) {
    _loadProfiles();
    final initialController = _ref.read(controllerProvider);
    syncFromController(initialController);
  }

  /// Synchronizes the pending profile values from live [controllerState] if the
  /// user has not manually modified the sliders, or if [force] is true.
  void syncFromController(ControllerState controllerState,
      {bool force = false}) {
    if (!force && _hasUserModified) return;
    if (controllerState.maxSpeedRaw <= 0 &&
        controllerState.maxLineCurrRaw <= 0) {
      return;
    }

    final kph = TuningConversions.maxSpeedRawToKph(controllerState.maxSpeedRaw);
    final lineAmps = controllerState.maxLineCurrA;
    final throttleMode = controllerState.rideMode.throttleResponseValue;

    var currentProfile = state.pendingProfile;
    var changed = false;

    if (kph > 0 && (currentProfile.maxSpeedKph - kph).abs() > 0.5) {
      currentProfile = currentProfile.copyWith(maxSpeedKph: kph);
      changed = true;
    }
    if (lineAmps > 0 && (currentProfile.maxLineCurrA - lineAmps).abs() > 0.5) {
      currentProfile = currentProfile.copyWith(maxLineCurrA: lineAmps);
      changed = true;
    }
    if (currentProfile.throttleResponse != throttleMode) {
      currentProfile = currentProfile.copyWith(throttleResponse: throttleMode);
      changed = true;
    }

    if (changed || force) {
      if (force) _hasUserModified = false;
      state = state.copyWith(
        pendingProfile: currentProfile,
        appliedSuccessfully: false,
      );
    }
  }

  void _loadProfiles() {
    final storage = _ref.read(storageServiceProvider);
    final profiles = storage.loadProfiles();
    state = state.copyWith(savedProfiles: profiles);
  }

  void toggleExpertMode([bool? value]) {
    state = state.copyWith(
      expertModeEnabled: value ?? !state.expertModeEnabled,
    );
  }

  void updateMaxSpeed(double kph) {
    _hasUserModified = true;
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(maxSpeedKph: kph),
      appliedSuccessfully: false,
    );
  }

  void updateMaxLineCurr(double amps) {
    _hasUserModified = true;
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(maxLineCurrA: amps),
      appliedSuccessfully: false,
    );
  }

  void updateMaxPhaseCurr(double amps) {
    _hasUserModified = true;
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(maxPhaseCurrA: amps),
      appliedSuccessfully: false,
    );
  }

  void updateRegen(double strength) {
    _hasUserModified = true;
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(regenStrength: strength),
      appliedSuccessfully: false,
    );
  }

  void updateThrottleResponse(int val) {
    _hasUserModified = true;
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(throttleResponse: val),
      appliedSuccessfully: false,
    );
  }

  void updateLowSpeedLineCurr(double pct) {
    _hasUserModified = true;
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(lowSpeedLineCurrPct: pct),
      appliedSuccessfully: false,
    );
  }

  void updateMidSpeedLineCurr(double pct) {
    _hasUserModified = true;
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(midSpeedLineCurrPct: pct),
      appliedSuccessfully: false,
    );
  }

  void updateBoostTime(int seconds) {
    _hasUserModified = true;
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(boostTimeSeconds: seconds),
      appliedSuccessfully: false,
    );
  }

  void updateLowVoltCutoff(double volts) {
    _hasUserModified = true;
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(lowVoltCutoffV: volts),
      appliedSuccessfully: false,
    );
  }

  void updateOverVoltCutoff(double volts) {
    _hasUserModified = true;
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(overVoltCutoffV: volts),
      appliedSuccessfully: false,
    );
  }

  void updateMotorTempLimit(double tempC) {
    _hasUserModified = true;
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(motorTempLimitC: tempC),
      appliedSuccessfully: false,
    );
  }

  void updateControllerTempLimit(double tempC) {
    _hasUserModified = true;
    state = state.copyWith(
      pendingProfile:
          state.pendingProfile.copyWith(controllerTempLimitC: tempC),
      appliedSuccessfully: false,
    );
  }

  void updateFluxWeakeningCurr(double amps) {
    _hasUserModified = true;
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(fluxWeakeningCurrA: amps),
      appliedSuccessfully: false,
    );
  }

  void updateReverseSpeed(double pct) {
    _hasUserModified = true;
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(reverseSpeedPct: pct),
      appliedSuccessfully: false,
    );
  }

  void updateSpeedRatios(List<int> ratios) {
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(speedRatios: ratios),
      appliedSuccessfully: false,
    );
  }

  void updateRegenRatios(List<int> ratios) {
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(regenRatios: ratios),
      appliedSuccessfully: false,
    );
  }

  void updateSpeedRatioPoint(int index, int ratioPct) {
    final list = List<int>.from(state.pendingProfile.speedRatios);
    if (index >= 0 && index < list.length) {
      list[index] = ratioPct.clamp(0, 100);
      state = state.copyWith(
        pendingProfile: state.pendingProfile.copyWith(speedRatios: list),
        appliedSuccessfully: false,
      );
    }
  }

  void updateRegenRatioPoint(int index, int regenPct) {
    final list = List<int>.from(state.pendingProfile.regenRatios);
    if (index >= 0 && index < list.length) {
      list[index] = regenPct.clamp(-100, 100);
      state = state.copyWith(
        pendingProfile: state.pendingProfile.copyWith(regenRatios: list),
        appliedSuccessfully: false,
      );
    }
  }

  void updatePinMapping(String pinKey, int pinNumber) {
    final pins = Map<String, int>.from(state.pendingProfile.pinMappings);
    pins[pinKey] = pinNumber;
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(pinMappings: pins),
      appliedSuccessfully: false,
    );
  }

  void updatePowerCurvePoint(int index, PowerPoint point) {
    final curve = List<PowerPoint>.from(state.pendingProfile.powerCurve);
    if (index >= 0 && index < curve.length) {
      curve[index] = point;
    }
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(powerCurve: curve),
      appliedSuccessfully: false,
    );
  }

  void loadPreset(TuningProfile preset) {
    _hasUserModified = true;
    state = state.copyWith(
      pendingProfile: preset,
      appliedSuccessfully: false,
      lastError: null,
    );
  }

  /// Applies all pending profile parameters to the controller.
  /// If [saveToFlash] is false (default), parameters are written directly to RAM
  /// and will cleanly revert to stock upon power cycling the bike.
  /// If [saveToFlash] is true, parameters are permanently committed into Flash/EEPROM.
  Future<bool> applyProfile({bool saveToFlash = false}) async {
    if (state.isApplying) return false;
    final decision = _ref.read(writeSafetyDecisionProvider);
    if (!decision.allowed) {
      state = state.copyWith(
        isApplying: false,
        isSavingToFlash: false,
        appliedSuccessfully: false,
        lastError: describeSafety(decision),
      );
      return false;
    }

    final profile = state.pendingProfile;
    final writes = <(int, int)>[
      (
        FardriverAddr.maxSpeed,
        TuningConversions.maxSpeedKphToRaw(profile.maxSpeedKph),
      ),
      (
        FardriverAddr.maxLineCurr,
        TuningConversions.maxLineCurrAToRaw(profile.maxLineCurrA),
      ),
      (
        FardriverAddr.throttleResponse,
        TuningConversions.throttleResponseToRaw(profile.throttleResponse),
      ),
    ];

    state = state.copyWith(
      isApplying: true,
      isSavingToFlash: saveToFlash,
      lastError: null,
    );

    final transport = _ref.read(bluetoothServiceProvider);
    for (final (address, value) in writes) {
      final written = await transport
          .write(ProtocolService.buildWritePacket(address, value));
      if (!written) {
        state = state.copyWith(
          isApplying: false,
          isSavingToFlash: false,
          appliedSuccessfully: false,
          lastError: 'Write to 0x${address.toRadixString(16).padLeft(2, '0')} '
              'was not acknowledged.',
        );
        return false;
      }
    }

    if (saveToFlash) {
      // Commit parameters to persistent Flash memory
      await transport.write(ProtocolService.saveParametersToFlashPacket());
    }

    _hasUserModified = false;
    state = state.copyWith(
      isApplying: false,
      isSavingToFlash: false,
      appliedSuccessfully: true,
      lastAppliedWasFlash: saveToFlash,
      activeRamMap: profile.name,
      lastError: null,
    );
    return true;
  }

  /// Clones the [source] profile into a new custom profile with [newName].
  Future<bool> cloneProfile(TuningProfile source, String newName) async {
    final cleanName = newName.trim();
    if (cleanName.isEmpty) return false;
    final storage = _ref.read(storageServiceProvider);
    final clone = source.copyWith(
      name: cleanName,
      createdAt: DateTime.now(),
      isStock: false,
    );
    await storage.saveProfile(clone);
    _loadProfiles();
    state = state.copyWith(pendingProfile: clone, appliedSuccessfully: false);
    return true;
  }

  /// Renames an existing custom profile. Stock baseline cannot be renamed.
  Future<bool> renameProfile(String oldName, String newName) async {
    final cleanName = newName.trim();
    if (cleanName.isEmpty || oldName == 'Stock Street Legal') return false;
    final storage = _ref.read(storageServiceProvider);
    final profiles = storage.loadProfiles();
    final idx = profiles.indexWhere((p) => p.name == oldName);
    if (idx < 0) return false;
    final updated = profiles[idx].copyWith(name: cleanName);
    await storage.deleteProfile(oldName);
    await storage.saveProfile(updated);
    _loadProfiles();
    if (state.pendingProfile.name == oldName) {
      state = state.copyWith(pendingProfile: updated);
    }
    return true;
  }

  /// Restores the factory baseline from `unmodified_basemap.heb` (Phase 15,
  /// T092). Every 16-bit register of the HEB is written back serially.
  Future<bool> restoreStock({List<int>? basemapBytes}) async {
    if (state.isRestoring || state.isApplying) return false;
    final decision = _ref.read(writeSafetyDecisionProvider);
    if (!decision.allowed) {
      state = state.copyWith(
        isRestoring: false,
        appliedSuccessfully: false,
        lastError: describeSafety(decision),
      );
      return false;
    }

    final planner = const StockHebRestorePlanner();
    try {
      final heb = basemapBytes != null
          ? HebFile.parse(basemapBytes)
          : await planner.loadFromAsset();
      final plan = planner.plan(heb);

      state = state.copyWith(isRestoring: true, lastError: null);

      final transport = _ref.read(bluetoothServiceProvider);
      for (final write in plan.writes) {
        final written = await transport.write(write.toPacket());
        if (!written) {
          state = state.copyWith(
            isRestoring: false,
            appliedSuccessfully: false,
            lastError: 'Restore aborted: write to $write failed.',
          );
          return false;
        }
      }

      state = state.copyWith(
        isRestoring: false,
        appliedSuccessfully: true,
        lastError: null,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isRestoring: false,
        appliedSuccessfully: false,
        lastError: 'Restore failed: $e',
      );
      return false;
    }
  }

  Future<void> saveCurrentProfile(String name) async {
    final storage = _ref.read(storageServiceProvider);
    final profile = state.pendingProfile.copyWith(
      name: name,
      createdAt: DateTime.now(),
      isStock: false,
    );
    await storage.saveProfile(profile);
    _loadProfiles();
  }

  Future<void> deleteProfile(String name) async {
    final storage = _ref.read(storageServiceProvider);
    await storage.deleteProfile(name);
    if (state.pendingProfile.name == name) {
      state = state.copyWith(
        pendingProfile: TuningProfile.custom(),
        appliedSuccessfully: false,
        lastError: null,
      );
    }
    _loadProfiles();
  }
}

final tuningProvider =
    StateNotifierProvider<TuningNotifier, TuningState>((ref) {
  final notifier = TuningNotifier(ref);
  ref.listen<ControllerState>(controllerProvider, (previous, next) {
    notifier.syncFromController(next);
  });
  return notifier;
});
