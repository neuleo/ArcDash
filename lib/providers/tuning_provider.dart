import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/controller_identity.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/services/heb_file_parser.dart';
import 'package:arcdash/services/protocol_service.dart';
import 'package:arcdash/services/stock_heb_restore.dart';
import 'package:arcdash/services/write_safety.dart';
import 'package:arcdash/utils/tuning_conversions.dart';

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
  final bool isRestoring;
  final String? lastError;
  final bool appliedSuccessfully;
  final List<TuningProfile> savedProfiles;

  const TuningState({
    required this.pendingProfile,
    this.isApplying = false,
    this.isRestoring = false,
    this.lastError,
    this.appliedSuccessfully = false,
    this.savedProfiles = const [],
  });

  TuningState copyWith({
    TuningProfile? pendingProfile,
    bool? isApplying,
    bool? isRestoring,
    String? lastError,
    bool? appliedSuccessfully,
    List<TuningProfile>? savedProfiles,
  }) =>
      TuningState(
        pendingProfile: pendingProfile ?? this.pendingProfile,
        isApplying: isApplying ?? this.isApplying,
        isRestoring: isRestoring ?? this.isRestoring,
        lastError: lastError,
        appliedSuccessfully: appliedSuccessfully ?? this.appliedSuccessfully,
        savedProfiles: savedProfiles ?? this.savedProfiles,
      );
}

class TuningNotifier extends StateNotifier<TuningState> {
  final Ref _ref;

  TuningNotifier(this._ref)
      : super(TuningState(pendingProfile: TuningProfile.custom())) {
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

  /// Applies all pending profile parameters to the controller (Phase 14, T090).
  ///
  /// Fail-closed: nothing is written unless the safety evaluator authorizes
  /// the write (connected, standstill at 0.0 km/h, fresh stream, no faults).
  /// The serialized write packets are sent over the BLE transport.
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

    state = state.copyWith(isApplying: true, lastError: null);

    final transport = _ref.read(bluetoothServiceProvider);
    for (final (address, value) in writes) {
      final written =
          await transport.write(ProtocolService.buildWritePacket(address, value));
      if (!written) {
        state = state.copyWith(
          isApplying: false,
          appliedSuccessfully: false,
          lastError:
              'Write to 0x${address.toRadixString(16).padLeft(2, '0')} '
              'was not acknowledged.',
        );
        return false;
      }
    }

    state = state.copyWith(
      isApplying: false,
      appliedSuccessfully: true,
      lastError: null,
    );
    return true;
  }

  /// Restores the factory baseline from `unmodified_basemap.heb` (Phase 15,
  /// T092). Every 16-bit register of the HEB is written back serially. The
  /// optional [basemapBytes] parameter allows injecting the file content
  /// (e.g. from tests); the bundled asset is used when omitted.
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
            lastError:
                'Restore aborted: write to $write failed.',
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
  return TuningNotifier(ref);
});
