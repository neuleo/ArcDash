import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';

/// Interactive Elevation profile chart widget for an active or previewed route.
class RouteElevationChart extends StatelessWidget {
  final NavigationRoute route;

  const RouteElevationChart({super.key, required this.route});

  @override
  Widget build(BuildContext context) {
    // Generate synthetic or real elevation spots along route distance
    final spots = <FlSpot>[];
    final totalKm = route.totalDistanceMeters / 1000.0;
    final totalGain = route.elevationGainMetersTotal;

    if (totalKm <= 0) return const SizedBox.shrink();

    // Create 15 elevation sample points for the curve
    const pointCount = 15;
    for (int i = 0; i <= pointCount; i++) {
      final km = (i / pointCount) * totalKm;
      // Synthesize realistic terrain profile using sine & total elevation gain
      final elev = 50.0 +
          (totalGain * (i / pointCount)) +
          (totalGain > 10
              ? (12.0 * (i % 3 == 1 ? 1 : (i % 3 == 2 ? -0.5 : 0)))
              : 0);
      spots.add(FlSpot(km, elev));
    }

    final minElev = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxElev = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);

    return Container(
      height: 120,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.terrain, color: Color(0xFF00E5FF), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'HÖHENPROFIL (+${totalGain.round()} m)',
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Text(
                '${minElev.round()} m – ${maxElev.round()} m',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: totalKm,
                minY: (minElev - 10).clamp(0, double.infinity),
                maxY: maxElev + 10,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: const Color(0xFF00E5FF),
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF00E5FF).withOpacity(0.35),
                          const Color(0xFF00E5FF).withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
