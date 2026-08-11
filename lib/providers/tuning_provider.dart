import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/controller_identity.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/services/write_safety.dart';

/// Identity of the connected controller. Parsed from live status during a
/// later phase; until then the fail-closed gate keeps writes blocked.
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
  final String? lastError;
  final bool appliedSuccessfully;
  final List<TuningProfile> savedProfiles;

  const TuningState({
    required this.pendingProfile,
    this.isApplying = false,
    this.lastError,
    this.appliedSuccessfully = false,
    this.savedProfiles = const [],
  });

  TuningState copyWith({
    TuningProfile? pendingProfile,
    bool? isApplying,
    String? lastError,
    bool? appliedSuccessfully,
    List<TuningProfile>? savedProfiles,
  }) =>
      TuningState(
        pendingProfile: pendingProfile ?? this.pendingProfile,
        isApplying: isApplying ?? this.isApplying,
        lastError: lastError,
        appliedSuccessfully: appliedSuccessfully ?? this.appliedSuccessfully,
        savedProfiles: savedProfiles ?? this.savedProfiles,
      );
}

class TuningNotifier extends StateNotifier<TuningState> {
  final Ref _ref;

  TuningNotifier(this._ref)
      : super(TuningState(pendingProfile: TuningProfile.trail())) {
    _loadProfiles();
  }

  void _loadProfiles() {
    final storage = _ref.read(storageServiceProvider);
    final profiles = storage.loadProfiles();
    state = state.copyWith(savedProfiles: profiles);
  }

  void updateMaxSpeed(double kph) {
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(maxSpeedKph: kph),
      appliedSuccessfully: false,
    );
  }

  void updateMaxLineCurr(double amps) {
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(maxLineCurrA: amps),
      appliedSuccessfully: false,
    );
  }

  void updateMaxPhaseCurr(double amps) {
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(maxPhaseCurrA: amps),
      appliedSuccessfully: false,
    );
  }

  void updateRegen(double strength) {
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(regenStrength: strength),
      appliedSuccessfully: false,
    );
  }

  void updateThrottleResponse(int val) {
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(throttleResponse: val),
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
    state = state.copyWith(
      pendingProfile: preset,
      appliedSuccessfully: false,
      lastError: null,
    );
  }

  /// Applies all pending profile parameters to the controller.
  ///
  /// Fail-closed: nothing is written unless the safety evaluator authorizes
  /// the write (connected, standstill at 0.0 km/h, fresh stream, no faults).
  Future<bool> applyProfile() async {
    if (state.isApplying) return false;
    final decision = _ref.read(writeSafetyDecisionProvider);
    if (!decision.allowed) {
      state = state.copyWith(
        isApplying: false,
        appliedSuccessfully: false,
        lastError: describeSafety(decision),
      );
      return false;
    }
    // Wiring the serialized BLE writes is part of Phase 14 (T090); the write
    // path stays read-only until then.
    state = state.copyWith(
      isApplying: false,
      appliedSuccessfully: false,
      lastError: 'Write engine not yet enabled — live writing ships in Phase 14.',
    );
    return false;
  }

  /// Restores stock parameters from backup.
  Future<bool> restoreStock() async {
    state = state.copyWith(
      lastError: 'Restore locked until the safe write engine is complete.',
    );
    return false;
  }

  Future<void> saveCurrentProfile(String name) async {
    final storage = _ref.read(storageServiceProvider);
    final profile = state.pendingProfile.copyWith(
      name: name,
      createdAt: DateTime.now(),
    );
    await storage.saveProfile(profile);
    _loadProfiles();
  }

  Future<void> deleteProfile(String name) async {
    final storage = _ref.read(storageServiceProvider);
    await storage.deleteProfile(name);
    _loadProfiles();
  }
}

final tuningProvider =
    StateNotifierProvider<TuningNotifier, TuningState>((ref) {
  return TuningNotifier(ref);
});
