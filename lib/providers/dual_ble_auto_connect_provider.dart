import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/providers/ant_bms_provider.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/services/dual_ble_auto_connect.dart';

/// Auto-remember coordinator. Watching this provider triggers background
/// reconnects for the last used controller and ANT BMS at app start.
final dualBleAutoConnectProvider = Provider<DualBleAutoConnect>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final controller = ref.watch(bluetoothServiceProvider);
  final bms = ref.watch(antBmsServiceProvider);
  final coordinator = DualBleAutoConnect(storage, controller, bms);
  coordinator.start();
  return coordinator;
});
