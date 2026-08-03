import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/controller_state.dart';
import 'package:arcdash/models/dashboard_layout.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DashboardLayout _dashboard = DashboardLayout.defaults();
  Timer? _saveTimer;
  bool _editing = false;
  bool _loaded = false;
  DashboardOrientation _editingOrientation = DashboardOrientation.portrait;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _dashboard = ref.read(storageServiceProvider).loadDashboardLayout();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () {
      ref.read(storageServiceProvider).saveDashboardLayout(_dashboard);
    });
  }

  DashboardOrientation get _currentOrientation =>
      MediaQuery.orientationOf(context) == Orientation.portrait
          ? DashboardOrientation.portrait
          : DashboardOrientation.landscape;

  DashboardOrientation get _activeOrientation =>
      _editing ? _editingOrientation : _currentOrientation;

  void _updateCurrent(DashboardOrientationLayout layout) {
    setState(
        () => _dashboard = _dashboard.withLayout(_activeOrientation, layout));
    _scheduleSave();
  }

  void _removeTile(DashboardTile tile) {
    final layout = _dashboard.layoutFor(_activeOrientation);
    _updateCurrent(layout.copyWith(
      tiles:
          layout.tiles.where((candidate) => candidate.id != tile.id).toList(),
    ));
  }

  void _moveTile(DashboardTile tile, int direction) {
    final layout = _dashboard.layoutFor(_activeOrientation);
    final index = layout.tiles.indexOf(tile);
    if (index < 0) return;
    final moved = direction.abs() > 1
        ? tile.copyWith(column: tile.column + direction.sign)
        : tile.copyWith(row: tile.row + direction);
    final tiles = [...layout.tiles]..[index] = moved;
    try {
      final next = layout.copyWith(tiles: tiles);
      next.validate();
      _updateCurrent(next);
    } on FormatException {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Diese Position ist belegt oder außerhalb des Rasters.')),
      );
    }
  }

  void _resizeTile(DashboardTile tile) {
    final layout = _dashboard.layoutFor(_activeOrientation);
    final index = layout.tiles.indexOf(tile);
    final nextWidth = tile.width == 1
        ? 2
        : tile.width == 2
            ? 3
            : 1;
    final resized = tile.copyWith(width: nextWidth);
    final tiles = [...layout.tiles]..[index] = resized;
    try {
      final next = layout.copyWith(tiles: tiles);
      next.validate();
      _updateCurrent(next);
    } on FormatException {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diese Größe passt nicht in das Layout.')),
      );
    }
  }

  void _resetCurrent() {
    _updateCurrent(DashboardLayout.defaults().layoutFor(_activeOrientation));
  }

  void _copyOrientation() {
    final source = _dashboard.layoutFor(_editingOrientation);
    final target = _editingOrientation == DashboardOrientation.portrait
        ? DashboardOrientation.landscape
        : DashboardOrientation.portrait;
    final targetGrid = _dashboard.layoutFor(target);
    final tiles = source.tiles
        .map((tile) => tile.copyWith(
              column: tile.column.clamp(0, targetGrid.columns - 1),
              row: tile.row.clamp(0, targetGrid.rows - 1),
              width: tile.width.clamp(1, targetGrid.columns),
              height: tile.height.clamp(1, targetGrid.rows),
            ))
        .toList();
    try {
      final copied = DashboardOrientationLayout(
        columns: targetGrid.columns,
        rows: targetGrid.rows,
        tiles: tiles,
      );
      copied.validate();
      setState(() => _dashboard = _dashboard.withLayout(target, copied));
      _scheduleSave();
    } on FormatException {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Das Layout passt nicht in diese Ausrichtung.')),
      );
    }
  }

  void _addMetric(DashboardMetric metric) {
    final layout = _dashboard.layoutFor(_activeOrientation);
    if (layout.tiles.any((tile) => tile.metric == metric)) return;
    final kind = metric == DashboardMetric.power
        ? DashboardTileKind.arc
        : metric == DashboardMetric.connection ||
                metric == DashboardMetric.errors
            ? DashboardTileKind.status
            : DashboardTileKind.value;
    for (var row = 0; row < layout.rows; row++) {
      for (var column = 0; column < layout.columns; column++) {
        final tile = DashboardTile(
          id: metric.name,
          metric: metric,
          kind: kind,
          column: column,
          row: row,
          width: 1,
          height: 1,
        );
        if (_fits(tile, layout)) {
          _updateCurrent(layout.copyWith(tiles: [...layout.tiles, tile]));
          return;
        }
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Im Raster ist kein Platz mehr.')),
    );
  }

  bool _fits(DashboardTile candidate, DashboardOrientationLayout layout) {
    if (candidate.column + candidate.width > layout.columns ||
        candidate.row + candidate.height > layout.rows) {
      return false;
    }
    return layout.tiles.every((tile) {
      final separated = candidate.column + candidate.width <= tile.column ||
          tile.column + tile.width <= candidate.column ||
          candidate.row + candidate.height <= tile.row ||
          tile.row + tile.height <= candidate.row;
      return tile.id == candidate.id || separated;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(controllerProvider);
    final connected = ref.watch(isConnectedProvider);
    final orientation = _activeOrientation;
    final layout = _dashboard.layoutFor(orientation);

    return Scaffold(
      backgroundColor: const Color(0xFF050608),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ARCDASH'),
            Text('RIDE COMPUTER',
                style: TextStyle(
                    fontSize: 9, letterSpacing: 1.8, color: Colors.white38)),
          ],
        ),
        actions: [
          _ConnectionPill(
            connected: connected,
            onTap: () => Navigator.of(context).pushNamed('/'),
          ),
          IconButton(
            tooltip:
                _editing ? 'Bearbeitung schließen' : 'Dashboard bearbeiten',
            onPressed: () => setState(() {
              _editing = !_editing;
              _editingOrientation = orientation;
            }),
            icon: Icon(_editing ? Icons.check : Icons.tune),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_editing)
              _EditorBar(
                orientation: _editingOrientation,
                onOrientationChanged: (value) =>
                    setState(() => _editingOrientation = value),
                onAdd: () => _showMetricPicker(),
                onCopy: _copyOrientation,
                onReset: _resetCurrent,
              ),
            Expanded(
              child: _DashboardCanvas(
                layout: layout,
                state: state,
                connected: connected,
                editing: _editing,
                onRemove: _removeTile,
                onMove: _moveTile,
                onResize: _resizeTile,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _editing
          ? null
          : NavigationBar(
              selectedIndex: 0,
              onDestinationSelected: (index) {
                if (index == 1) Navigator.of(context).pushNamed('/stats');
                if (index == 2) Navigator.of(context).pushNamed('/settings');
              },
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.speed), label: 'Cockpit'),
                NavigationDestination(
                    icon: Icon(Icons.route_outlined), label: 'Fahrten'),
                NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    label: 'Einstellungen'),
              ],
            ),
    );
  }

  Future<void> _showMetricPicker() async {
    final selected = await showModalBottomSheet<DashboardMetric>(
      context: context,
      backgroundColor: const Color(0xFF11151A),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: DashboardMetric.values
              .map((metric) => ListTile(
                    title: Text(_metricLabel(metric)),
                    leading: const Icon(Icons.add),
                    onTap: () => Navigator.pop(context, metric),
                  ))
              .toList(),
        ),
      ),
    );
    if (selected != null) _addMetric(selected);
  }
}

class _EditorBar extends StatelessWidget {
  final DashboardOrientation orientation;
  final ValueChanged<DashboardOrientation> onOrientationChanged;
  final VoidCallback onAdd;
  final VoidCallback onCopy;
  final VoidCallback onReset;

  const _EditorBar({
    required this.orientation,
    required this.onOrientationChanged,
    required this.onAdd,
    required this.onCopy,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        color: const Color(0xFF11151A),
        child: Row(
          children: [
            SegmentedButton<DashboardOrientation>(
              segments: const [
                ButtonSegment(
                    value: DashboardOrientation.portrait, label: Text('Hoch')),
                ButtonSegment(
                    value: DashboardOrientation.landscape, label: Text('Quer')),
              ],
              selected: {orientation},
              onSelectionChanged: (value) => onOrientationChanged(value.single),
            ),
            const Spacer(),
            IconButton(
                tooltip: 'Wert hinzufügen',
                onPressed: onAdd,
                icon: const Icon(Icons.add_box_outlined)),
            IconButton(
                tooltip: 'Ausrichtung kopieren',
                onPressed: onCopy,
                icon: const Icon(Icons.copy)),
            IconButton(
                tooltip: 'Standardlayout',
                onPressed: onReset,
                icon: const Icon(Icons.restart_alt)),
          ],
        ),
      );
}

class _DashboardCanvas extends StatelessWidget {
  final DashboardOrientationLayout layout;
  final ControllerState state;
  final bool connected;
  final bool editing;
  final ValueChanged<DashboardTile> onRemove;
  final void Function(DashboardTile, int) onMove;
  final ValueChanged<DashboardTile> onResize;

  const _DashboardCanvas({
    required this.layout,
    required this.state,
    required this.connected,
    required this.editing,
    required this.onRemove,
    required this.onMove,
    required this.onResize,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final cellWidth = constraints.maxWidth / layout.columns;
          final cellHeight = constraints.maxHeight / layout.rows;
          return Stack(
            children: [
              for (final tile in layout.tiles)
                Positioned(
                  left: tile.column * cellWidth + 6,
                  top: tile.row * cellHeight + 6,
                  width: tile.width * cellWidth - 12,
                  height: tile.height * cellHeight - 12,
                  child: _TileFrame(
                    tile: tile,
                    editing: editing,
                    onRemove: () => onRemove(tile),
                    onMoveLeft: () => onMove(tile, -10),
                    onMoveRight: () => onMove(tile, 10),
                    onMoveUp: () => onMove(tile, -1),
                    onMoveDown: () => onMove(tile, 1),
                    onResize: () => onResize(tile),
                    child: _MetricView(
                        tile: tile, state: state, connected: connected),
                  ),
                ),
            ],
          );
        },
      );
}

class _TileFrame extends StatelessWidget {
  final DashboardTile tile;
  final bool editing;
  final Widget child;
  final VoidCallback onRemove;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onResize;

  const _TileFrame({
    required this.tile,
    required this.editing,
    required this.child,
    required this.onRemove,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onResize,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: tile.metric == DashboardMetric.speed
              ? const RadialGradient(
                  colors: [Color(0xFF16232A), Color(0xFF080B0E)], radius: 0.9)
              : const LinearGradient(
                  colors: [Color(0xFF12171C), Color(0xFF0B0E12)]),
          borderRadius: BorderRadius.circular(
              tile.metric == DashboardMetric.speed ? 28 : 18),
          border: Border.all(
            color: editing
                ? const Color(0xFF00E5FF)
                : tile.metric == DashboardMetric.speed
                    ? const Color(0xFF263943)
                    : const Color(0xFF202833),
            width: editing ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: tile.height == 1
                    ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                    : const EdgeInsets.all(14),
                child: child,
              ),
            ),
            if (editing)
              Positioned(
                right: 2,
                top: 2,
                child: PopupMenuButton<_TileCommand>(
                  tooltip: '${_metricLabel(tile.metric)} bearbeiten',
                  onSelected: (command) => switch (command) {
                    _TileCommand.left => onMoveLeft(),
                    _TileCommand.right => onMoveRight(),
                    _TileCommand.up => onMoveUp(),
                    _TileCommand.down => onMoveDown(),
                    _TileCommand.resize => onResize(),
                    _TileCommand.remove => onRemove(),
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                        value: _TileCommand.left, child: Text('Nach links')),
                    PopupMenuItem(
                        value: _TileCommand.right, child: Text('Nach rechts')),
                    PopupMenuItem(
                        value: _TileCommand.up, child: Text('Nach oben')),
                    PopupMenuItem(
                        value: _TileCommand.down, child: Text('Nach unten')),
                    PopupMenuItem(
                        value: _TileCommand.resize,
                        child: Text('Größe ändern')),
                    PopupMenuItem(
                        value: _TileCommand.remove, child: Text('Entfernen')),
                  ],
                  icon: const Icon(Icons.more_vert),
                ),
              ),
          ],
        ),
      );
}

enum _TileCommand { left, right, up, down, resize, remove }

class _MetricView extends StatelessWidget {
  final DashboardTile tile;
  final ControllerState state;
  final bool connected;

  const _MetricView(
      {required this.tile, required this.state, required this.connected});

  @override
  Widget build(BuildContext context) {
    final reading = _reading(tile.metric);
    final label = _metricLabel(tile.metric);
    if (tile.metric == DashboardMetric.speed) {
      return _SpeedDial(speedKph: state.speedKph, connected: connected);
    }
    if (tile.metric == DashboardMetric.power) {
      return _PowerMeter(powerKw: state.powerKw, connected: connected);
    }
    final valueColor = tile.metric == DashboardMetric.errors
        ? state.hasAnyFault
            ? const Color(0xFFFF5470)
            : const Color(0xFF54E39E)
        : Colors.white;
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxHeight < 70;
      final labelWidget = Text(label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white54, fontSize: 10, letterSpacing: 1.1));
      final valueWidget = Text(reading,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: valueColor,
            fontSize: compact
                ? 17
                : tile.kind == DashboardTileKind.status
                    ? 18
                    : 28,
            fontWeight: FontWeight.w800,
          ));
      if (compact) {
        return Row(children: [
          Expanded(child: labelWidget),
          const SizedBox(width: 8),
          Flexible(child: valueWidget),
        ]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [labelWidget, const SizedBox(height: 6), valueWidget],
      );
    });
  }

  String _reading(DashboardMetric metric) {
    if (!connected && metric != DashboardMetric.connection) return '—';
    return switch (metric) {
      DashboardMetric.speed => '${state.speedKph.toStringAsFixed(0)} km/h',
      DashboardMetric.power => '${state.powerKw.toStringAsFixed(1)} kW',
      DashboardMetric.voltage => '${state.voltageV.toStringAsFixed(1)} V',
      DashboardMetric.current => '${state.currentA.toStringAsFixed(1)} A',
      DashboardMetric.soc => '${state.batteryPercent.toStringAsFixed(0)} %',
      DashboardMetric.range => '— km',
      DashboardMetric.profile => state.rideMode.displayName,
      DashboardMetric.gear => state.gear == 0 ? '—' : state.gear.toString(),
      DashboardMetric.motorTemperature =>
        '${state.motorTempC.toStringAsFixed(0)} °C',
      DashboardMetric.controllerTemperature =>
        '${state.controllerTempC.toStringAsFixed(0)} °C',
      DashboardMetric.errors => state.hasAnyFault ? 'Fehler' : 'Keine Fehler',
      DashboardMetric.connection => connected ? 'Verbunden' : 'Getrennt',
    };
  }
}

class _ConnectionPill extends StatelessWidget {
  final bool connected;
  final VoidCallback onTap;

  const _ConnectionPill({required this.connected, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Material(
          color: connected ? const Color(0xFF123328) : const Color(0xFF271D20),
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.bluetooth,
                      size: 16,
                      color: connected
                          ? const Color(0xFF54E39E)
                          : const Color(0xFFFFB45C)),
                  const SizedBox(width: 6),
                  Text(connected ? 'LIVE' : 'VERBINDEN',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                ],
              ),
            ),
          ),
        ),
      );
}

class _SpeedDial extends StatelessWidget {
  final double speedKph;
  final bool connected;

  const _SpeedDial({required this.speedKph, required this.connected});

  @override
  Widget build(BuildContext context) => Semantics(
        key: const Key('speed-dial'),
        label: connected
            ? 'Geschwindigkeit ${speedKph.round()} Kilometer pro Stunde'
            : 'Geschwindigkeit unbekannt, nicht verbunden',
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                  child: CustomPaint(
                      painter: _SpeedDialPainter(
                          speedKph: connected ? speedKph : 0,
                          active: connected))),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(connected ? speedKph.round().toString() : '–',
                      style: TextStyle(
                          fontSize: math.min(constraints.maxHeight * 0.29, 82),
                          height: 0.9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -3)),
                  const SizedBox(height: 8),
                  const Text('km/h',
                      style: TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2)),
                  const SizedBox(height: 8),
                  Text(connected ? 'CONTROLLER' : 'KEINE DATEN',
                      style: TextStyle(
                          color: connected
                              ? const Color(0xFF00E5FF)
                              : const Color(0xFFFFB45C),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5)),
                ],
              ),
            ],
          ),
        ),
      );
}

class _SpeedDialPainter extends CustomPainter {
  final double speedKph;
  final bool active;

  const _SpeedDialPainter({required this.speedKph, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.39;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = math.pi * 0.72;
    const sweep = math.pi * 1.56;
    final track = Paint()
      ..color = const Color(0xFF243039)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, track);
    final progress = (speedKph / 120).clamp(0.0, 1.0);
    final activePaint = Paint()
      ..shader = const SweepGradient(
          colors: [Color(0xFF00E5FF), Color(0xFF54E39E), Color(0xFFFFB45C)],
          stops: [0, 0.72, 1]).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    if (active) {
      canvas.drawArc(rect, start, sweep * progress, false, activePaint);
    }
    final tickPaint = Paint()..strokeWidth = 2;
    for (var i = 0; i <= 12; i++) {
      final angle = start + sweep * i / 12;
      tickPaint.color =
          i / 12 <= progress && active ? Colors.white : const Color(0xFF52616A);
      final outer =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius + 18);
      final inner = center +
          Offset(math.cos(angle), math.sin(angle)) *
              (radius + (i.isEven ? 4 : 9));
      canvas.drawLine(inner, outer, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedDialPainter oldDelegate) =>
      oldDelegate.speedKph != speedKph || oldDelegate.active != active;
}

class _PowerMeter extends StatelessWidget {
  final double powerKw;
  final bool connected;

  const _PowerMeter({required this.powerKw, required this.connected});

  @override
  Widget build(BuildContext context) {
    final regen = powerKw < 0;
    final color = !connected
        ? Colors.white24
        : regen
            ? const Color(0xFF54E39E)
            : const Color(0xFF00E5FF);
    final normalized = connected ? (powerKw.abs() / 20).clamp(0.0, 1.0) : 0.0;
    return Semantics(
      label: connected
          ? '${regen ? 'Rekuperation' : 'Leistung'} ${powerKw.abs().toStringAsFixed(1)} Kilowatt'
          : 'Leistung unbekannt',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(regen ? Icons.battery_charging_full : Icons.bolt,
                  color: color, size: 18),
              const SizedBox(width: 8),
              Text(regen ? 'REKUPERATION' : 'LEISTUNG',
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5)),
              const Spacer(),
              Text(
                  connected ? '${powerKw.abs().toStringAsFixed(1)} kW' : '– kW',
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
                value: normalized,
                minHeight: 12,
                backgroundColor: const Color(0xFF263039),
                valueColor: AlwaysStoppedAnimation(color)),
          ),
        ],
      ),
    );
  }
}

String _metricLabel(DashboardMetric metric) => switch (metric) {
      DashboardMetric.speed => 'Geschwindigkeit',
      DashboardMetric.power => 'Leistung',
      DashboardMetric.voltage => 'Spannung',
      DashboardMetric.current => 'Strom',
      DashboardMetric.soc => 'Batterie',
      DashboardMetric.range => 'Reichweite',
      DashboardMetric.profile => 'Profil',
      DashboardMetric.gear => 'Gang',
      DashboardMetric.motorTemperature => 'Motortemperatur',
      DashboardMetric.controllerTemperature => 'Controllertemperatur',
      DashboardMetric.errors => 'Fehler',
      DashboardMetric.connection => 'Verbindung',
    };
