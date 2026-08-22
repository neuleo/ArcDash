import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:arcdash/models/ride_log.dart';

/// Full ride analysis: per-channel min/max/avg table, interactive chart with
/// a draggable window (start/end handles) and a second-precise inspector.
class RideAnalysisScreen extends StatefulWidget {
  final RideLog log;

  const RideAnalysisScreen({super.key, required this.log});

  @override
  State<RideAnalysisScreen> createState() => _RideAnalysisScreenState();
}

class _RideAnalysisScreenState extends State<RideAnalysisScreen> {
  RideChannel _channel = RideChannel.speed;

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
  }

  List<RideLogSample> get _windowSamples => widget.log.samples
      .where((s) => s.t >= _winStart.floor() && s.t <= _winEnd.ceil())
      .toList();

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
            const Text('FAHRT-ANALYSE',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2)),
            Text(
              '${df.format(log.startedAt)} · ${_fmtDuration(log.duration)} · ${log.distanceKm.toStringAsFixed(1)} km',
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Channel selector ----
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: RideChannel.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final c = RideChannel.values[i];
                  final selected = c == _channel;
                  return ChoiceChip(
                    label: Text(c.label),
                    selected: selected,
                    onSelected: (_) => setState(() => _channel = c),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.black : Colors.white70,
                    ),
                    selectedColor: const Color(0xFF00E5FF),
                    backgroundColor: const Color(0xFF1A2030),
                    side: BorderSide(
                      color: selected
                          ? const Color(0xFF00E5FF)
                          : const Color(0xFF2A3548),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),

            // ---- Interactive chart with draggable window ----
            _WindowChart(
              log: log,
              channel: _channel,
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
              'Zeitfenster ziehen: ${_fmtSec(_winStart)} → ${_fmtSec(_winEnd)} '
              '(Antippen im Graph zeigt den exakten Wert dieser Sekunde)',
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
            const SizedBox(height: 20),

            // ---- Second inspector ----
            if (_inspectT != null) ...[
              _SecondInspector(log: log, t: _inspectT!),
              const SizedBox(height: 20),
            ],

            // ---- Min / Max / Avg table over the whole ride ----
            _StatsTable(log: log),

            // ---- Window stats ----
            const SizedBox(height: 20),
            _WindowStats(samples: _windowSamples, channel: _channel),
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

// ---------------------------------------------------------------------------
// Chart with two drag handles for the analysis window.
// ---------------------------------------------------------------------------
class _WindowChart extends StatelessWidget {
  final RideLog log;
  final RideChannel channel;
  final double winStart;
  final double winEnd;
  final int? inspectT;
  final void Function(double start, double end) onWindowChanged;
  final void Function(int t) onTapAt;

  const _WindowChart({
    required this.log,
    required this.channel,
    required this.winStart,
    required this.winEnd,
    required this.inspectT,
    required this.onWindowChanged,
    required this.onTapAt,
  });

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (final s in log.samples) {
      final v = RideLog.valueOf(s, channel);
      if (v != null) spots.add(FlSpot(s.t.toDouble(), v));
    }

    return SizedBox(
      height: 240,
      child: Column(
        children: [
          Expanded(
            child: LineChart(
              LineChartData(
                minY: _autoMin(spots),
                maxY: _autoMax(spots),
                gridData: const FlGridData(show: true),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: _tickInterval(winEnd - winStart),
                      getTitlesWidget: (v, meta) => Text(_mmss(v),
                          style: const TextStyle(
                              fontSize: 9, color: Colors.white24)),
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
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: false,
                    barWidth: 1.4,
                    color: const Color(0xFF00E5FF),
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF00E5FF).withOpacity(0.08),
                    ),
                  ),
                  if (inspectT != null)
                    LineChartBarData(
                      spots: spots.where((p) => p.x == inspectT).toList(),
                      isCurved: false,
                      barWidth: 0,
                      dotData: const FlDotData(show: true),
                      color: const Color(0xFFFFB45C),
                    ),
                ],
                betweenBarsData: [],
                extraLinesData: ExtraLinesData(
                  verticalLines: [
                    VerticalLine(
                        x: winStart,
                        color: const Color(0xFFFFB45C),
                        strokeWidth: 1),
                    VerticalLine(
                        x: winEnd,
                        color: const Color(0xFFFFB45C),
                        strokeWidth: 1),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Window range slider (both thumbs)
          RangeSlider(
            values: RangeValues(winStart, winEnd),
            min: 0,
            max: log.samples.isEmpty
                ? 1
                : log.samples.last.t.toDouble().clamp(1, double.infinity),
            divisions: log.samples.isEmpty ? 1 : log.samples.last.t,
            activeColor: const Color(0xFFFFB45C),
            inactiveColor: const Color(0xFF2A3548),
            labels: RangeLabels(_mmss(winStart), _mmss(winEnd)),
            onChanged: (v) => onWindowChanged(v.start, v.end),
          ),
        ],
      ),
    );
  }

  double? _autoMin(List<FlSpot> s) => s.isEmpty
      ? null
      : s.map((e) => e.y).reduce((a, b) => a < b ? a : b) * 0.98;
  double? _autoMax(List<FlSpot> s) => s.isEmpty
      ? null
      : s.map((e) => e.y).reduce((a, b) => a > b ? a : b) * 1.02;

  double _tickInterval(double seconds) {
    if (seconds <= 30) return 5;
    if (seconds <= 120) return 15;
    if (seconds <= 600) return 60;
    return 300;
  }

  static String _mmss(double v) {
    final m = v ~/ 60;
    final s = (v % 60).round();
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Second-precise inspector card.
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
        border: Border.all(color: const Color(0xFFFFB45C).withOpacity(0.5)),
      ),
      child: s == null
          ? Text('Sekunde $t: keine Aufzeichnung',
              style: const TextStyle(color: Colors.white38))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SEKUNDE $t',
                    style: const TextStyle(
                        color: Color(0xFFFFB45C),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  children: [
                    for (final c in RideChannel.values)
                      if (RideLog.valueOf(s, c) != null)
                        _InspectorValue(
                            label: c.label,
                            value: RideLog.valueOf(s, c)!,
                            unit: c.unit),
                  ],
                ),
              ],
            ),
    );
  }
}

class _InspectorValue extends StatelessWidget {
  final String label;
  final double value;
  final String unit;

  const _InspectorValue(
      {required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    final formatted = value.abs() >= 100
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.white38)),
        Text('$formatted $unit',
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      ],
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
            border: TableBorder(
              horizontalInside:
                  BorderSide(color: Colors.white.withOpacity(0.06)),
            ),
            children: [
              const TableRow(children: [
                _HeadCell('Kanal'),
                _HeadCell('MIN'),
                _HeadCell('MAX'),
                _HeadCell('Ø'),
              ]),
              for (final c in RideChannel.values) _buildRow(c, log.statsFor(c)),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _buildRow(RideChannel c, ChannelStats st) {
    String fmt(double? v) => v == null
        ? '—'
        : (v.abs() >= 100 ? v.round().toString() : v.toStringAsFixed(1));
    return TableRow(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text('${c.label} (${c.unit})',
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ),
      _ValueCell(fmt(st.min)),
      _ValueCell(fmt(st.max), highlight: true),
      _ValueCell(fmt(st.avg)),
    ]);
  }
}

class _HeadCell extends StatelessWidget {
  final String text;
  const _HeadCell(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: Colors.white38)),
      );
}

class _ValueCell extends StatelessWidget {
  final String text;
  final bool highlight;
  const _ValueCell(this.text, {this.highlight = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                color: highlight ? const Color(0xFF54E39E) : Colors.white70)),
      );
}

// ---------------------------------------------------------------------------
// Stats of the currently selected window.
// ---------------------------------------------------------------------------
class _WindowStats extends StatelessWidget {
  final List<RideLogSample> samples;
  final RideChannel channel;

  const _WindowStats({required this.samples, required this.channel});

  @override
  Widget build(BuildContext context) {
    double? min, max, sum;
    var n = 0;
    var distKm = 0.0;
    for (final s in samples) {
      final v = RideLog.valueOf(s, channel);
      if (v != null) {
        if (min == null || v < min) min = v;
        if (max == null || v > max) max = v;
        sum = (sum ?? 0) + v;
        n++;
      }
      final sp = s.speedKph;
      if (sp != null) distKm += sp / 3600.0;
    }
    final avg = n > 0 ? sum! / n : null;
    String fmt(double? v) => v == null
        ? '—'
        : (v.abs() >= 100 ? v.round().toString() : v.toStringAsFixed(1));

    return Row(
      children: [
        _WindowStat(label: 'Fenster MIN', value: fmt(min)),
        _WindowStat(label: 'MAX', value: fmt(max)),
        _WindowStat(label: 'Ø', value: fmt(avg)),
        _WindowStat(label: 'km im Fenster', value: distKm.toStringAsFixed(2)),
      ],
    );
  }
}

class _WindowStat extends StatelessWidget {
  final String label;
  final String value;
  const _WindowStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF10151C),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 9, color: Colors.white38),
                  textAlign: TextAlign.center),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ],
          ),
        ),
      );
}
