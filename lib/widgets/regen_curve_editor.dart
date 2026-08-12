import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RegenCurveEditor extends StatefulWidget {
  final List<int>
      regenRatios; // 18 points: 500..9000 RPM (values in range -100..0%)
  final ValueChanged<List<int>> onChanged;
  final bool enabled;

  const RegenCurveEditor({
    super.key,
    required this.regenRatios,
    required this.onChanged,
    this.enabled = true,
  });

  static const List<int> rpmSteps = [
    500,
    1000,
    1500,
    2000,
    2500,
    3000,
    3500,
    4000,
    4500,
    5000,
    5500,
    6000,
    6500,
    7000,
    7500,
    8000,
    8500,
    9000,
  ];

  @override
  State<RegenCurveEditor> createState() => _RegenCurveEditorState();
}

class _RegenCurveEditorState extends State<RegenCurveEditor> {
  int _selectedPointIndex = 0;

  @override
  Widget build(BuildContext context) {
    final values = widget.regenRatios.length == 18
        ? widget.regenRatios
        : const [
            -13,
            -16,
            -19,
            -22,
            -25,
            -25,
            -25,
            -25,
            -25,
            -25,
            -25,
            -25,
            -25,
            -25,
            -25,
            -25,
            -25,
            0
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: const [
                Icon(Icons.bolt, color: Color(0xFF39FF14), size: 18),
                SizedBox(width: 8),
                Text(
                  'REKUPERATIONS-KURVE (500–9000 RPM)',
                  style: TextStyle(
                    color: Color(0xFF39FF14),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF39FF14).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: const Color(0xFF39FF14).withValues(alpha: 0.3)),
              ),
              child: Text(
                '${RegenCurveEditor.rpmSteps[_selectedPointIndex]} RPM: ${values[_selectedPointIndex]}%',
                style: const TextStyle(
                  color: Color(0xFF39FF14),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Line Chart for Negative Regen Percentages
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                getDrawingHorizontalLine: (_) => const FlLine(
                  color: Color(0xFF1A2030),
                  strokeWidth: 1,
                ),
                getDrawingVerticalLine: (_) => const FlLine(
                  color: Color(0xFF1A2030),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) {
                      final idx = val.toInt();
                      if (idx == 0 || idx == 5 || idx == 11 || idx == 17) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${RegenCurveEditor.rpmSteps[idx]}',
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                    reservedSize: 20,
                    interval: 1,
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) => Text(
                      '${val.toInt()}%',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 9,
                      ),
                    ),
                    reservedSize: 36,
                    interval: 25,
                  ),
                ),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: 17,
              minY: -100,
              maxY: 0,
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (int i = 0; i < 18; i++)
                      FlSpot(i.toDouble(), values[i].toDouble()),
                  ],
                  isCurved: true,
                  color: const Color(0xFF39FF14),
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, bar, index) {
                      final isSelected = index == _selectedPointIndex;
                      return FlDotCirclePainter(
                        radius: isSelected ? 6 : 3,
                        color: isSelected
                            ? const Color(0xFF00E5FF)
                            : const Color(0xFF39FF14),
                        strokeWidth: isSelected ? 2 : 1,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF39FF14).withValues(alpha: 0.0),
                        const Color(0xFF39FF14).withValues(alpha: 0.25),
                      ],
                    ),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                enabled: true,
                touchCallback: (event, response) {
                  if (event is FlTapUpEvent && response?.lineBarSpots != null) {
                    final spot = response!.lineBarSpots!.first;
                    setState(() {
                      _selectedPointIndex = spot.spotIndex.clamp(0, 17);
                    });
                    HapticFeedback.selectionClick();
                  }
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Quick Preset Buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _PresetButton(
              label: 'Stock Leopard (-25%)',
              onPressed: widget.enabled
                  ? () {
                      HapticFeedback.selectionClick();
                      widget.onChanged(const [
                        -13,
                        -16,
                        -19,
                        -22,
                        -25,
                        -25,
                        -25,
                        -25,
                        -25,
                        -25,
                        -25,
                        -25,
                        -25,
                        -25,
                        -25,
                        -25,
                        -25,
                        0
                      ]);
                    }
                  : null,
            ),
            _PresetButton(
              label: 'Strong Regen (-50%)',
              onPressed: widget.enabled
                  ? () {
                      HapticFeedback.selectionClick();
                      final list = List<int>.generate(18, (i) {
                        if (i == 17) return 0;
                        return (-20 - (i * 30 / 16)).round().clamp(-100, 0);
                      });
                      widget.onChanged(list);
                    }
                  : null,
            ),
            _PresetButton(
              label: 'Off / Coast (0%)',
              onPressed: widget.enabled
                  ? () {
                      HapticFeedback.selectionClick();
                      widget.onChanged(List<int>.filled(18, 0));
                    }
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Slider for Selected RPM Point
        Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                '${RegenCurveEditor.rpmSteps[_selectedPointIndex]} RPM',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: const Color(0xFF39FF14),
                  inactiveTrackColor: const Color(0xFF1E293B),
                  thumbColor: const Color(0xFF39FF14),
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayColor: const Color(0xFF39FF14).withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: values[_selectedPointIndex].toDouble(),
                  min: -100,
                  max: 0,
                  divisions: 100,
                  onChanged: widget.enabled
                      ? (val) {
                          final updated = List<int>.from(values);
                          updated[_selectedPointIndex] = val.round();
                          widget.onChanged(updated);
                        }
                      : null,
                ),
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(
                '${values[_selectedPointIndex]}%',
                style: const TextStyle(
                  color: Color(0xFF39FF14),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PresetButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _PresetButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF94A3B8),
        side: const BorderSide(color: Color(0xFF1E293B)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
