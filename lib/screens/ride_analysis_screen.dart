import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:arcdash/models/ride_log.dart';

/// Full ride analysis: multi-channel overlaid interactive chart with
/// draggable time window, custom channel selection & preset filters,
/// second-precise inspector, and per-channel statistics table.
class RideAnalysisScreen extends StatefulWidget {
  final RideLog log;

  const RideAnalysisScreen({super.key, required this.log});

  @override
  State<RideAnalysisScreen> createState() => _RideAnalysisScreenState();
}

enum _AnalysisPreset {
  speedOnly('Nur Speed'),
  performance('Performance (Speed + Power + Strom)'),
  thermal('Thermisch (Motor + Ctrl + BMS)'),
  battery('Batterie (Volt + Strom + SOC)'),
  all('Alle verfÃ¼gbaren');

  final String label;
  const _AnalysisPreset(this.label);
}

class _RideAnalysisScreenState extends State<RideAnalysisScreen> {
  // Selected channels for multi-curve overlay
  late Set<RideChannel> _selectedChannels;

  // Draggable window in seconds [windowStart, windowEnd].
  late double _winStart;
  late double _winEnd;
  int? _inspectT; // selected second inside the window

  @override
  void initState() {
    super.initState();
    final maxT =
        widget.log.samples.isEmpty ? 1.0 : widget.log.samples.last.t.toDouble();
    _winStart = 0;
    _winEnd = maxT;
    // Default channels: Speed and Power for comprehensive overview
    _selectedChannels = {RideChannel.speed, RideChannel.power};
  }

  List<RideLogSample> get _windowSamples => widget.log.samples
      .where((s) => s.t >= _winStart.floor() && s.t <= _winEnd.ceil())
      .toList();

  void _applyPreset(_AnalysisPreset preset) {
    setState(() {
      switch (preset) {
        case _AnalysisPreset.speedOnly:
          _selectedChannels = {RideChannel.speed};
          break;
        case _AnalysisPreset.performance:
          _selectedChannels = {
            RideChannel.speed,
            RideChannel.power,
            RideChannel.current,
          };
          break;
        case _AnalysisPreset.thermal:
          _selectedChannels = {
            RideChannel.motorTemp,
            RideChannel.controllerTemp,
            RideChannel.bmsTemp,
          };
          break;
        case _AnalysisPreset.battery:
          _selectedChannels = {
            RideChannel.voltage,
            RideChannel.current,
            RideChannel.soc,
            RideChannel.power,
          };
          break;
        case _AnalysisPreset.all:
          _selectedChannels = RideChannel.values.toSet();
          break;
      }
      _inspectT = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final df = DateFormat('dd.MM.yyyy HH:mm:ss');

    return Scaffold(
      backgroundColor: const Color(0xFF080B0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('FAHRT-ANALYSE & TELEMETRIE',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2)),
            Text(
              '${df.format(log.startedAt)} Â· ${_fmtDuration(log.duration)} Â· ${log.distanceKm.toStringAsFixed(1)} km',
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<_AnalysisPreset>(
            icon: const Icon(Icons.tune, color: Color(0xFF00E5FF)),
            tooltip: 'Kanal-Presets',
            onSelected: _applyPreset,
            itemBuilder: (_) => [
              for (final p in _AnalysisPreset.values)
                PopupMenuItem(value: p, child: Text(p.label)),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Preset Quick-Chips ----
            Row(
              children: [
                const Text('PRESETS: ',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.white38,
                        fontWeight: FontWeight.bold)),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _PresetButton('Speed',
                            () => _applyPreset(_AnalysisPreset.speedOnly)),
                        const SizedBox(width: 6),
                        _PresetButton('Power & Speed',
                            () => _applyPreset(_AnalysisPreset.performance)),
                        const SizedBox(width: 6),
                        _PresetButton('Thermal / Temps',
                            () => _applyPreset(_AnalysisPreset.thermal)),
                        const SizedBox(width: 6),
                        _PresetButton('Battery / Akku',
                            () => _applyPreset(_AnalysisPreset.battery)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ---- Multi-Channel selector chips ----
            const Text(
              'ANGEZEIGTE KANÃLE (Antippen zum Ein-/Ausblenden):',
              style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in RideChannel.values) ...[
                  FilterChip(
                    label: Text(c.label),
                    avatar: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: c.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    selected: _selectedChannels.contains(c),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedChannels.add(c);
                        } else {
                          if (_selectedChannels.length > 1) {
                            _selectedChannels.remove(c);
                          }
                        }
                        _inspectT = null;
                      });
                    },
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _selectedChannels.contains(c)
                          ? Colors.white
                          : Colors.white54,
                    ),
                    selectedColor: c.color.withOpacity(0.25),
                    backgroundColor: const Color(0xFF141A23),
                    side: BorderSide(
                      color: _selectedChannels.contains(c)
                          ? c.color
                          : const Color(0xFF222B38),
                      width: 1.2,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // ---- Interactive Multi-Curve Chart with draggable window ----
            _MultiWindowChart(
              log: log,
              selectedChannels: _selectedChannels,
              winStart: _winStart,
              winEnd: _winEnd,
              inspectT: _inspectT,
              onWindowChanged: (a, b) => setState(() {
                _winStart = a;
                _winEnd = b;
                _inspectT = null;
              }),
              onTapAt: (t) => setState(() => _inspectT = t),
            ),
            const SizedBox(height: 6),
            Text(
              'Zeitfenster ziehen: ${_fmtSec(_winStart)} â ${_fmtSec(_winEnd)} '
              'â¢ Antippen im Graph inspiziert den exakten Sekundenwert',
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
            const SizedBox(height: 18),

            // ---- Second inspector ----
            if (_inspectT != null) ...[
              _SecondInspector(log: log, t: _inspectT!),
              const SizedBox(height: 18),
            ],

            // ---- Window stats for active channels ----
            _MultiWindowStats(
                samples: _windowSamples, channels: _selectedChannels),
            const SizedBox(height: 20),

            // ---- Full-ride min/max/average table across all channels ----
            _StatsTable(log: log),
          ],
        ),
      ),
    );
  }

  static String _fmtSec(double s) {
    final m = s ~/ 60;
    final sec = (s % 60).floor();
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  static String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0
        ? '${h}h ${m.toString().padLeft(2, '0')}min'
        : '${m}min ${s.toString().padLeft(2, '0')}s';
  }
}

class _PresetButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PresetButton(this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      labelStyle: const TextStyle(
          fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
      backgroundColor: const Color(0xFF1E2836),
      side: const BorderSide(color: Color(0xFF2E3D52)),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      onPressed: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Multi-channel overlaid chart with normalized/scaled lines and legend.
// ---------------------------------------------------------------------------
class _MultiWindowChart extends StatelessWidget {
  final RideLog log;
  final Set<RideChannel> selectedChannels;
  final double winStart;
  final double winEnd;
  final int? inspectT;
  final void Function(double start, double end) onWindowChanged;
  final void Function(int t) onTapAt;

  const _MultiWindowChart({
    required this.log,
    required this.selectedChannels,
    required this.winStart,
    required this.winEnd,
    required this.inspectT,
    required this.onWindowChanged,
    required this.onTapAt,
  });

  @override
  Widget build(BuildContext context) {
    final lineBars = <LineChartBarData>[];

    double? globalMin;
    double? globalMax;

    // If multiple channels are selected, normalize each channel to 0-100% for comparison
    // or display primary unit if only 1 channel is selected.
    final isSingleChannel = selectedChannels.length == 1;
    final singleCh = isSingleChannel ? selectedChannels.first : null;

    for (final channel in selectedChannels) {
      final channelSpots = <FlSpot>[];
      double? chMin;
      double? chMax;

      for (final s in log.samples) {
        final val = RideLog.valueOf(s, channel);
        if (val != null) {
          if (chMin == null || val < chMin) chMin = val;
          if (chMax == null || val > chMax) chMax = val;
        }
      }

      final range = (chMax != null && chMin != null && chMax > chMin)
          ? (chMax - chMin)
          : 1.0;

      for (final s in log.samples) {
        final val = RideLog.valueOf(s, channel);
        if (val != null) {
          if (isSingleChannel) {
            channelSpots.add(FlSpot(s.t.toDouble(), val));
            if (globalMin == null || val < globalMin) globalMin = val;
            if (globalMax == null || val > globalMax) globalMax = val;
          } else {
            // Normalized percentage (0..100) on shared overlay axis
            final normY = ((val - (chMin ?? 0.0)) / range) * 100.0;
            channelSpots.add(FlSpot(s.t.toDouble(), normY));
          }
        }
      }

      if (channelSpots.isNotEmpty) {
        lineBars.add(LineChartBarData(
          spots: channelSpots,
          isCurved: true,
          curveSmoothness: 0.15,
          barWidth: 1.8,
          color: channel.color,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: isSingleChannel,
            color: channel.color.withOpacity(0.08),
          ),
        ));
      }
    }

    // Add inspection marker if active
    if (inspectT != null) {
      for (final bar in List<LineChartBarData>.from(lineBars)) {
        final match = bar.spots.where((p) => p.x == inspectT).toList();
        if (match.isNotEmpty) {
          lineBars.add(LineChartBarData(
            spots: match,
            barWidth: 0,
            color: bar.color,
            dotData: const FlDotData(show: true),
          ));
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF10151C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2836)),
      ),
      child: Column(
        children: [
          // Legend row
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final c in selectedChannels)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: c.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${c.label} (${c.unit})',
                      style: TextStyle(
                          fontSize: 10,
                          color: c.color,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minY: isSingleChannel ? globalMin : 0,
                maxY: isSingleChannel ? globalMax : 100,
                gridData: FlGridData(
                  show: true,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: Color(0xFF1A2230), strokeWidth: 1),
                  getDrawingVerticalLine: (_) =>
                      const FlLine(color: Color(0xFF1A2230), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: isSingleChannel,
                      reservedSize: 32,
                      getTitlesWidget: (v, meta) => Text(
                        v.toStringAsFixed(0),
                        style:
                            const TextStyle(fontSize: 9, color: Colors.white30),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: _tickInterval(winEnd - winStart),
                      getTitlesWidget: (v, meta) => Text(_mmss(v),
                          style: const TextStyle(
                              fontSize: 9, color: Colors.white30)),
                    ),
                  ),
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                ),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchCallback: (evt, resp) {
                    if (evt is FlTapUpEvent &&
                        resp?.lineBarSpots?.isNotEmpty == true) {
                      onTapAt(resp!.lineBarSpots!.first.x.round());
                    }
                  },
                ),
                lineBarsData: lineBars,
                extraLinesData: ExtraLinesData(
                  verticalLines: [
                    VerticalLine(
                        x: winStart,
                        color: const Color(0xFFFFB45C),
                        strokeWidth: 1.2),
                    VerticalLine(
                        x: winEnd,
                        color: const Color(0xFFFFB45C),
                        strokeWidth: 1.2),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Window range slider
          RangeSlider(
            values: RangeValues(winStart, winEnd),
            min: 0,
            max: log.samples.isEmpty
                ? 1
                : log.samples.last.t.toDouble().clamp(1, double.infinity),
            divisions: log.samples.isEmpty ? 1 : log.samples.last.t,
            activeColor: const Color(0xFFFFB45C),
            inactiveColor: const Color(0xFF222B38),
            labels: RangeLabels(_mmss(winStart), _mmss(winEnd)),
            onChanged: (v) => onWindowChanged(v.start, v.end),
          ),
        ],
      ),
    );
  }

  static double _tickInterval(double windowSpan) {
    if (windowSpan <= 60) return 10;
    if (windowSpan <= 300) return 30;
    if (windowSpan <= 1200) return 120;
    return 600;
  }

  static String _mmss(double v) {
    final m = v ~/ 60;
    final s = (v % 60).round();
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Second-precise inspector card with color badges.
// ---------------------------------------------------------------------------
class _SecondInspector extends StatelessWidget {
  final RideLog log;
  final int t;

  const _SecondInspector({required this.log, required this.t});

  @override
  Widget build(BuildContext context) {
    final matches = log.samples.where((s) => s.t == t).toList();
    final s = matches.isEmpty ? null : matches.first;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF10151C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB45C).withOpacity(0.6)),
      ),
      child: s == null
          ? Text('Sekunde $t: keine Aufzeichnung',
              style: const TextStyle(color: Colors.white38))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_searching,
                        color: Color(0xFFFFB45C), size: 16),
                    const SizedBox(width: 8),
                    Text('MESSWERTE BEI SEKUNDE $t (${_fmtSec(t.toDouble())})',
                        style: const TextStyle(
                            color: Color(0xFFFFB45C),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5)),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  children: [
                    for (final c in RideChannel.values)
                      if (RideLog.valueOf(s, c) != null)
                        _InspectorValue(
                          label: c.label,
                          value: RideLog.valueOf(s, c)!,
                          unit: c.unit,
                          color: c.color,
                        ),
                  ],
                ),
              ],
            ),
    );
  }

  static String _fmtSec(double s) {
    final m = s ~/ 60;
    final sec = (s % 60).floor();
    return '$m:${sec.toString().padLeft(2, '0')} min';
  }
}

class _InspectorValue extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final Color color;

  const _InspectorValue({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final formatted = value.abs() >= 100
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 10, color: color.withOpacity(0.8))),
          const SizedBox(height: 2),
          Text('$formatted $unit',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Window statistics cards for multiple channels.
// ---------------------------------------------------------------------------
class _MultiWindowStats extends StatelessWidget {
  final List<RideLogSample> samples;
  final Set<RideChannel> channels;

  const _MultiWindowStats({required this.samples, required this.channels});

  @override
  Widget build(BuildContext context) {
    var distKm = 0.0;
    for (final s in samples) {
      if (s.speedKph != null) distKm += s.speedKph! / 3600.0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WERTE IM GEWÃHLTEN ZEITFENSTER (${distKm.toStringAsFixed(2)} km):',
          style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.bold,
              letterSpacing: 1),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final c in channels)
                _ChannelWindowCard(samples: samples, channel: c),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChannelWindowCard extends StatelessWidget {
  final List<RideLogSample> samples;
  final RideChannel channel;

  const _ChannelWindowCard({required this.samples, required this.channel});

  @override
  Widget build(BuildContext context) {
    double? min, max, sum;
    var n = 0;
    for (final s in samples) {
      final v = RideLog.valueOf(s, channel);
      if (v != null) {
        if (min == null || v < min) min = v;
        if (max == null || v > max) max = v;
        sum = (sum ?? 0) + v;
        n++;
      }
    }
    final avg = n > 0 ? sum! / n : null;
    String fmt(double? v) => v == null
        ? 'â'
        : (v.abs() >= 100 ? v.round().toString() : v.toStringAsFixed(1));

    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF10151C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: channel.color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(channel.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  color: channel.color,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Ã ${fmt(avg)} ${channel.unit}',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          const SizedBox(height: 2),
          Text('Min: ${fmt(min)}  Max: ${fmt(max)}',
              style: const TextStyle(fontSize: 10, color: Colors.white38)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full-ride min/max/average table across every recorded channel.
// ---------------------------------------------------------------------------
class _StatsTable extends StatelessWidget {
  final RideLog log;

  const _StatsTable({required this.log});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF10151C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E2836)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ECKWERTE GESAMTE FAHRT',
              style: TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2)),
          const SizedBox(height: 10),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(4),
              1: FlexColumnWidth(3),
              2: FlexColumnWidth(3),
              3: FlexColumnWidth(3),
            },
            children: [
              const TableRow(
                children: [
                  Text('Kanal',
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
                  Text('Min',
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
                  Text('Max',
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
                  Text('Ã',
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
              for (final c in RideChannel.values) _buildRow(c, log.statsFor(c)),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _buildRow(RideChannel channel, ChannelStats stats) {
    String fmt(double? v) => v == null
        ? 'â'
        : (v.abs() >= 100 ? v.round().toString() : v.toStringAsFixed(1));
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: channel.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${channel.label} (${channel.unit})',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(fmt(stats.min),
              style: const TextStyle(fontSize: 11, color: Colors.white)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(fmt(stats.max),
              style: const TextStyle(fontSize: 11, color: Colors.white)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(fmt(stats.avg),
              style: const TextStyle(fontSize: 11, color: Colors.white)),
        ),
      ],
    );
  }
}
