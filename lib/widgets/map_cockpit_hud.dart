import 'package:flutter/material.dart';

/// Mini cockpit HUD overlay for the map screen showing live speed, SOC, and kW.
class MapCockpitHud extends StatelessWidget {
  final double speedKph;
  final int socPercent;
  final double powerKw;
  final double? motorTempC;

  const MapCockpitHud({
    super.key,
    required this.speedKph,
    required this.socPercent,
    required this.powerKw,
    this.motorTempC,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC0D1117),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Speed
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                speedKph.round().toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const Text(
                'KM/H',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Container(width: 1, height: 26, color: Colors.white12),
          const SizedBox(width: 14),

          // Battery SOC %
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    socPercent > 20
                        ? Icons.battery_charging_full
                        : Icons.battery_alert,
                    color: socPercent > 20
                        ? const Color(0xFF54E39E)
                        : Colors.orangeAccent,
                    size: 13,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '$socPercent %',
                    style: TextStyle(
                      color: socPercent > 20
                          ? const Color(0xFF54E39E)
                          : Colors.orangeAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text(
                '${powerKw.toStringAsFixed(1)} kW',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
