import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show FlutterBluePlus, BluetoothAdapterState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/ant_bms_provider.dart';
import 'package:arcdash/providers/controller_provider.dart'
    show storageServiceProvider;
import 'package:arcdash/services/ant_bms_service.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/widgets/bike_selector_card.dart';
import 'package:arcdash/widgets/connection_status_bar.dart';
import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/services/android_permission_service.dart';
import 'package:arcdash/services/diagnostic_log_exporter.dart';

class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  bool _isScanning = false;
  String? _connectingId;
  bool _showAllDevices = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);

    // Explicitly request both Bluetooth and Fine Location permissions on Android
    try {
      final permService =
          const AndroidPermissionService(PermissionHandlerRequester());
      await permService.requestForSdk(33);
      await permService.requestForSdk(30);
    } catch (_) {}

    // Wait until the BT adapter is on (handles macOS/iOS/Android initialization delay)
    final BluetoothAdapterState adapterState;
    try {
      adapterState = await FlutterBluePlus.adapterState
          .firstWhere((s) => s != BluetoothAdapterState.unknown)
          .timeout(const Duration(seconds: 5),
              onTimeout: () => BluetoothAdapterState.unavailable);
    } on UnsupportedError {
      if (mounted) setState(() => _isScanning = false);
      return;
    }
    if (adapterState != BluetoothAdapterState.on) {
      if (mounted) {
        setState(() => _isScanning = false);
        _showError(AppStrings.of(context).text(AppText.bluetoothOff));
      }
      return;
    }
    final service = ref.read(bluetoothServiceProvider);
    await service.startScan(
      timeout: const Duration(seconds: 10),
      showAllDevices: _showAllDevices,
    );
    if (mounted) setState(() => _isScanning = false);
  }

  void _toggleShowAllDevices(bool value) {
    setState(() => _showAllDevices = value);
    _startScan();
  }

  Future<void> _connect(DiscoveredDongle dongle,
      {bool forceBms = false}) async {
    setState(() => _connectingId = dongle.device.remoteId.str);
    final storage = ref.read(storageServiceProvider);
    final isBms =
        forceBms || isAntBmsName(dongle.name, dongle.device.remoteId.str);
    var success = false;

    if (isBms) {
      // Parallel ANT BMS session (runs alongside the FarDriver controller).
      await ref.read(antBmsStateProvider.notifier).connect(dongle);
      success = ref.read(isBmsConnectedProvider);
      if (success) {
        await storage.saveLastBmsId(dongle.device.remoteId.str);
      }
    } else {
      final service = ref.read(bluetoothServiceProvider);
      success = await service.connect(dongle);
      if (success) {
        await storage.saveLastControllerId(dongle.device.remoteId.str);
      }
    }

    if (mounted) {
      setState(() => _connectingId = null);
      if (success) {
        if (isBms) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('ANT BMS verbunden (parallel zum Controller)'),
            backgroundColor: Color(0xFF123328),
            behavior: SnackBarBehavior.floating,
          ));
        } else {
          Navigator.of(context).pushReplacementNamed('/dashboard');
        }
      } else {
        _showError(AppStrings.of(context).text(AppText.connectionFailed));
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFFFF1744),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider).valueOrNull ??
        DongleConnectionState.idle;
    final scanResults = ref.watch(scanResultsProvider).valueOrNull ?? [];
    final bmsState = ref.watch(antBmsConnectionStateProvider).valueOrNull ??
        DongleConnectionState.idle;
    final bmsName = ref.watch(antBmsDeviceNameProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF080B0E),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // Logo / header
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF00E5FF).withOpacity(0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.electric_bolt,
                    color: Color(0xFF00E5FF),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ARCDASH',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.5,
                      ),
                    ),
                    Text(
                      AppStrings.of(context).text(AppText.controllerConnect),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Status bars
            Row(
              children: [
                Expanded(
                  child: ConnectionStatusBar(
                    state: connectionState,
                    deviceName: null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ConnectionStatusBar(
                    state: bmsState,
                    deviceName: bmsName,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Bike Selector & Quick-Pairing
            const BikeSelectorCard(),
            const SizedBox(height: 20),
            // Scan controls
            Row(
              children: [
                Text(
                  AppStrings.of(context).text(AppText.nearbyDongles),
                  style: const TextStyle(
                    color: Color(0xFF4A5568),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _isScanning ? null : _startScan,
                  icon: _isScanning
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF00E5FF),
                          ),
                        )
                      : const Icon(Icons.refresh, size: 16),
                  label: Text(AppStrings.of(context)
                      .text(_isScanning ? AppText.searching : AppText.search)),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF00E5FF),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Filter toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF111518),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A3548)),
              ),
              child: Row(
                children: [
                  Icon(
                    _showAllDevices ? Icons.devices : Icons.bike_scooter,
                    color: const Color(0xFF00E5FF),
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _showAllDevices
                          ? 'Alle Geräte anzeigen'
                          : 'Nur Bike-Hardware anzeigen',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Switch(
                    value: _showAllDevices,
                    onChanged: _toggleShowAllDevices,
                    activeColor: const Color(0xFF00E5FF),
                    activeTrackColor: const Color(0xFF00E5FF).withOpacity(0.3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Device list
            if (scanResults.isEmpty)
              _EmptyState(isScanning: _isScanning)
            else
              for (final dongle in scanResults) ...[
                _DongleCard(
                  dongle: dongle,
                  isConnecting: _connectingId == dongle.device.remoteId.str,
                  onConnectAsController: () => _connect(dongle),
                  onConnectAsBms: () => _connect(dongle, forceBms: true),
                ),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 12),
            // Info footer
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2030).withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF2A3548),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Color(0xFF4A5568),
                    size: 16,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _showAllDevices
                          ? 'Zeigt alle Bluetooth-Geräte in deiner Umgebung an (manuelle Suche).'
                          : 'Zeigt nur Bike-Hardware an: FarDriver-Tuner-Dongles und ANT-BMS.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Diagnostic Log Share Button
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00E5FF),
                side: const BorderSide(color: Color(0xFF00E5FF)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                final diagnostics = ref.read(diagnosticsLogProvider);
                DiagnosticLogExporter.shareOrCopy(context, diagnostics);
              },
              icon: const Icon(Icons.share, size: 18),
              label: const Text(
                'Diagnose-Log teilen',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _DongleCard extends StatelessWidget {
  final DiscoveredDongle dongle;
  final bool isConnecting;
  final VoidCallback onConnectAsController;
  final VoidCallback onConnectAsBms;

  const _DongleCard({
    required this.dongle,
    required this.isConnecting,
    required this.onConnectAsController,
    required this.onConnectAsBms,
  });

  @override
  Widget build(BuildContext context) {
    final isBmsHint = isAntBmsName(dongle.name, dongle.device.remoteId.str);
    return PopupMenuButton<String>(
      onSelected: (choice) {
        if (choice == 'controller') {
          onConnectAsController();
        } else if (choice == 'bms') {
          onConnectAsBms();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'controller',
          child: Row(
            children: const [
              Icon(Icons.speed, color: Color(0xFF00E5FF), size: 18),
              SizedBox(width: 10),
              Text('Als FarDriver Controller verbinden'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'bms',
          child: Row(
            children: const [
              Icon(Icons.battery_charging_full,
                  color: Color(0xFF54E39E), size: 18),
              SizedBox(width: 10),
              Text('Als ANT BMS verbinden'),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF111518),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isBmsHint
                  ? const Color(0xFF54E39E).withOpacity(0.4)
                  : const Color(0xFF2A3548)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (isBmsHint
                        ? const Color(0xFF54E39E)
                        : const Color(0xFF00E5FF))
                    .withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isBmsHint ? Icons.battery_charging_full : Icons.bluetooth,
                color: isBmsHint
                    ? const Color(0xFF54E39E)
                    : const Color(0xFF00E5FF),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          dongle.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isBmsHint) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF54E39E).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('BMS',
                              style: TextStyle(
                                  color: Color(0xFF54E39E),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    dongle.device.remoteId.str,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.35),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Text(
                  '${dongle.rssi} dBm',
                  style: const TextStyle(
                    color: Color(0xFF4A5568),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 12),
                isConnecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF00E5FF),
                        ),
                      )
                    : const Icon(
                        Icons.chevron_right,
                        color: Color(0xFF4A5568),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isScanning;
  const _EmptyState({required this.isScanning});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bluetooth_searching,
              size: 56,
              color: const Color(0xFF2A3548),
            ),
            const SizedBox(height: 16),
            Text(
              AppStrings.of(context).text(
                  isScanning ? AppText.searchingDongles : AppText.noDongles),
              style: const TextStyle(
                color: Color(0xFF4A5568),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isScanning
                  ? 'Make sure your bike is on and\nthe dongle is connected'
                  : AppStrings.of(context).text(AppText.searchAgain),
              style: const TextStyle(
                color: Color(0xFF2A3548),
                fontSize: 13,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
