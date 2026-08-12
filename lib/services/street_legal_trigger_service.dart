import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/providers/tuning_provider.dart';
import 'package:arcdash/services/foreground_service_bridge.dart';
import 'package:arcdash/services/macrodroid_contract.dart';

final foregroundServiceBridgeProvider =
    Provider<ForegroundServiceBridge>((ref) {
  final bridge = ForegroundServiceBridge();
  ref.onDispose(bridge.dispose);
  return bridge;
});

class StreetLegalTriggerService {
  final Ref _ref;
  final ForegroundServiceBridge _bridge;
  final MacroDroidContract _contract;
  StreamSubscription<String>? _subscription;

  StreetLegalTriggerService({
    required Ref ref,
    required ForegroundServiceBridge bridge,
    MacroDroidContract contract = const MacroDroidContract(),
  })  : _ref = ref,
        _bridge = bridge,
        _contract = contract {
    _subscription = _bridge.onMacroDroidTrigger.listen(_handleTrigger);
  }

  Future<bool> handleAction(String actionName) => _handleTrigger(actionName);

  Future<bool> _handleTrigger(String actionName) async {
    final request = _contract.parse(actionName: actionName);
    if (request == null) {
      await _bridge.vibrateError();
      return false;
    }

    final safety = _ref.read(writeSafetyDecisionProvider);
    if (!safety.allowed) {
      await _bridge.vibrateError();
      return false;
    }

    final tuningNotifier = _ref.read(tuningProvider.notifier);
    tuningNotifier.loadPreset(TuningProfile.streetLegal());
    final success = await tuningNotifier.applyProfile();

    if (success) {
      await _bridge.vibrateSuccess();
      await _bridge.updateNotification('Street Legal aktiv (45 km/h)');
      return true;
    } else {
      await _bridge.vibrateError();
      return false;
    }
  }

  void dispose() {
    _subscription?.cancel();
  }
}

final streetLegalTriggerServiceProvider =
    Provider<StreetLegalTriggerService>((ref) {
  final bridge = ref.watch(foregroundServiceBridgeProvider);
  final service = StreetLegalTriggerService(ref: ref, bridge: bridge);
  ref.onDispose(service.dispose);
  return service;
});
