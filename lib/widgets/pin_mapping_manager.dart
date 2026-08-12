import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PinMappingManager extends StatelessWidget {
  final Map<String, int> pinMappings;
  final Function(String pinKey, int pinNumber) onChanged;
  final bool enabled;

  const PinMappingManager({
    super.key,
    required this.pinMappings,
    required this.onChanged,
    this.enabled = true,
  });

  static const Map<int, String> pinNames = {
    0: '0 - NC (Disabled)',
    1: '1 - PIN24',
    2: '2 - PIN15 (CAN RX)',
    3: '3 - PIN5 (CAN TX)',
    4: '4 - PIN17',
    5: '5 - PIN14',
    6: '6 - PIN3',
    7: '7 - PIN8',
    8: '8 - PB4',
    10: '10 - PIN2',
    11: '11 - PIN18',
    12: '12 - PIN9',
    13: '13 - PD1',
    15: '15 - Invalid (Off)',
  };

  static const List<({String key, String label, IconData icon})> pinFeatures = [
    (key: 'boostPin', label: 'Boost Mode Pin', icon: Icons.bolt),
    (key: 'cruisePin', label: 'Cruise Control Pin', icon: Icons.speed),
    (
      key: 'sideStandPin',
      label: 'Seitenständer Pin (BC)',
      icon: Icons.two_wheeler
    ),
    (
      key: 'pausePin',
      label: 'Parksperre / Pause Pin (P)',
      icon: Icons.local_parking
    ),
    (
      key: 'lowSpeedPin',
      label: 'Modus 1 (Low Speed / SDL) Pin',
      icon: Icons.eco_outlined
    ),
    (
      key: 'highSpeedPin',
      label: 'Modus 3 (High Speed / SDH) Pin',
      icon: Icons.rocket_launch
    ),
    (
      key: 'reversePin',
      label: 'Rückwärtsgang Pin (RE)',
      icon: Icons.arrow_back
    ),
    (
      key: 'forwardPin',
      label: 'Vorwärtsgang Pin (FW)',
      icon: Icons.arrow_forward
    ),
    (
      key: 'speedLimitPin',
      label: 'Speed Limit Schalter Pin',
      icon: Icons.speed
    ),
    (
      key: 'chargePin',
      label: 'Ladeerkennung Pin (CHG)',
      icon: Icons.ev_station
    ),
    (
      key: 'seatPin',
      label: 'Sitzschalter Pin (Seat)',
      icon: Icons.airline_seat_recline_normal
    ),
    (
      key: 'antiTheftPin',
      label: 'Diebstahlschutz Pin (FD)',
      icon: Icons.security
    ),
    (
      key: 'switchVolPin',
      label: 'Spannungs-Umschaltung Pin',
      icon: Icons.electric_meter
    ),
    (key: 'repairPin', label: 'One-Touch Reparatur Pin', icon: Icons.build),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.cable, color: Color(0xFFFF9800), size: 18),
            SizedBox(width: 8),
            Text(
              'HARDWARE PIN-BELEGUNG (FUNKTIONSSCHALTER)',
              style: TextStyle(
                color: Color(0xFFFF9800),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < pinFeatures.length; i++) ...[
                _PinRow(
                  feature: pinFeatures[i],
                  selectedPin: pinMappings[pinFeatures[i].key] ?? 15,
                  enabled: enabled,
                  onChanged: (val) {
                    HapticFeedback.selectionClick();
                    onChanged(pinFeatures[i].key, val);
                  },
                ),
                if (i < pinFeatures.length - 1)
                  const Divider(color: Color(0xFF1E293B), height: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PinRow extends StatelessWidget {
  final ({String key, String label, IconData icon}) feature;
  final int selectedPin;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _PinRow({
    required this.feature,
    required this.selectedPin,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(feature.icon, color: const Color(0xFF94A3B8), size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            feature.label,
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF080B0E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: PinMappingManager.pinNames.containsKey(selectedPin)
                  ? selectedPin
                  : 15,
              dropdownColor: const Color(0xFF0F172A),
              style: const TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              isDense: true,
              icon: const Icon(Icons.arrow_drop_down,
                  color: Color(0xFF94A3B8), size: 18),
              items: PinMappingManager.pinNames.entries.map((entry) {
                return DropdownMenuItem<int>(
                  value: entry.key,
                  child: Text(entry.value),
                );
              }).toList(),
              onChanged:
                  enabled ? (val) => val != null ? onChanged(val) : null : null,
            ),
          ),
        ),
      ],
    );
  }
}
