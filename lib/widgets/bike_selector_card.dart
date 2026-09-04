import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/bike_profile.dart';
import 'package:arcdash/providers/bike_selector_provider.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/ant_bms_provider.dart';
import 'package:arcdash/widgets/bike_edit_modal.dart';

/// Interactive Bike Selector Card & Quick Connect UI:
/// - List of user-configured bikes (e.g., "Mein Arctic Leopard", "Bike Frau")
/// - 1-Tap Quick Connect (connects FarDriver Controller + ANT BMS simultaneously)
/// - Radio/Toggle for Auto-Connect preference (Auto-connect this bike, another, or none)
/// - Edit/Add Bike flow
class BikeSelectorCard extends ConsumerWidget {
  const BikeSelectorCard({super.key});

  void _showBikeModal(BuildContext context, [BikeProfile? bike]) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D1117),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => BikeEditModal(initialBike: bike),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bikeState = ref.watch(bikeSelectorProvider);
    final bikeNotifier = ref.read(bikeSelectorProvider.notifier);

    final isControllerConnected = ref.watch(isConnectedProvider);
    final isBmsConnected = ref.watch(isBmsConnectedProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111518),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFF00E5FF).withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.two_wheeler,
                          color: Color(0xFF00E5FF), size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Flexible(
                      child: Text(
                        'MEINE BIKES',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => _showBikeModal(context),
                icon: const Icon(Icons.add, size: 14, color: Color(0xFF00E5FF)),
                label: const Text(
                  '+ BIKE',
                  style: TextStyle(
                    color: Color(0xFF00E5FF),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (bikeState.bikes.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline, color: Colors.white54, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Noch kein Bike konfiguriert. Tippe auf "+ NEUES BIKE", um Controller & BMS fest einem Bike zuzuweisen.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                for (final bike in bikeState.bikes) ...[
                  _BikeItemTile(
                    bike: bike,
                    isSelected: bikeState.selectedBikeId == bike.id,
                    isAutoConnect: bikeState.autoConnectBikeId == bike.id,
                    isConnecting: bikeState.isConnecting &&
                        bikeState.connectingBikeId == bike.id,
                    isSessionActive: (bikeState.selectedBikeId == bike.id) &&
                        (isControllerConnected || isBmsConnected),
                    onConnect: () => bikeNotifier.connectBike(bike),
                    onEdit: () => _showBikeModal(context, bike),
                    onSetAutoConnect: (enabled) {
                      bikeNotifier.setAutoConnectBike(enabled ? bike.id : null);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          if (bikeState.statusMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              bikeState.statusMessage!,
              style: const TextStyle(
                  color: Color(0xFF54E39E),
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }
}

class _BikeItemTile extends StatelessWidget {
  final BikeProfile bike;
  final bool isSelected;
  final bool isAutoConnect;
  final bool isConnecting;
  final bool isSessionActive;
  final VoidCallback onConnect;
  final VoidCallback onEdit;
  final ValueChanged<bool> onSetAutoConnect;

  const _BikeItemTile({
    required this.bike,
    required this.isSelected,
    required this.isAutoConnect,
    required this.isConnecting,
    required this.isSessionActive,
    required this.onConnect,
    required this.onEdit,
    required this.onSetAutoConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSessionActive
              ? const Color(0xFF54E39E)
              : (isSelected
                  ? const Color(0xFF00E5FF).withOpacity(0.5)
                  : Colors.white12),
          width: isSessionActive ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.electric_moped,
                color:
                    isSessionActive ? const Color(0xFF54E39E) : Colors.white70,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          bike.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (isAutoConnect) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'AUTO',
                              style: TextStyle(
                                color: Color(0xFF00E5FF),
                                fontWeight: FontWeight.w900,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ctrl: ${bike.controllerName.isNotEmpty ? bike.controllerName : "None"}'
                      ' · BMS: ${bike.bmsId.isNotEmpty ? bike.bmsName : "None"}',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    color: Colors.white38, size: 18),
                tooltip: 'Bike bearbeiten',
                onPressed: onEdit,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Connect Button (1-Tap Dual Connect)
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSessionActive
                        ? const Color(0xFF123328)
                        : const Color(0xFF00E5FF),
                    foregroundColor: isSessionActive
                        ? const Color(0xFF54E39E)
                        : Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isConnecting ? null : onConnect,
                  icon: isConnecting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : Icon(
                          isSessionActive
                              ? Icons.check_circle
                              : Icons.bluetooth_connected,
                          size: 16),
                  label: Text(
                    isConnecting
                        ? 'VERBINDE...'
                        : (isSessionActive
                            ? 'VERBUNDEN (CTRL & BMS)'
                            : 'BIKE VERBINDEN'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.8),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Auto-Connect toggle chip
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onSetAutoConnect(!isAutoConnect),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isAutoConnect
                          ? const Color(0xFF00E5FF).withOpacity(0.12)
                          : Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isAutoConnect
                            ? const Color(0xFF00E5FF)
                            : Colors.white12,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isAutoConnect
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: 16,
                          color: isAutoConnect
                              ? const Color(0xFF00E5FF)
                              : Colors.white38,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Auto-Start',
                          style: TextStyle(
                            color: isAutoConnect
                                ? const Color(0xFF00E5FF)
                                : Colors.white54,
                            fontSize: 11,
                            fontWeight: isAutoConnect
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
