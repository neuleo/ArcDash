import 'package:flutter/material.dart';
import 'package:arcdash/models/ant_bms_state.dart';
import 'package:arcdash/utils/ant_bms_parser.dart';

/// Interactive ANT BMS monitor: per-cell bar chart (Cell 1..20) with
/// green/orange/red balance colour coding plus Min/Max/Delta, SOC,
/// temperatures and MOSFET switch states.
class BmsCellMonitor extends StatelessWidget {
  final AntBmsState? state;

  const BmsCellMonitor({super.key, this.state});

  static const Color _balanced = Color(0xFF39FF14);
  static const Color _elevated = Color(0xFFFF9800);
  static const Color _critical = Color(0xFFFF1744);

  @override
  Widget build(BuildContext context) {
    final bms = state;
    if (bms == null || bms.cellCount == 0) {
      return _EmptyBms();
    }

    final minMv = bms.minCellVoltageMv!;
    final maxMv = bms.maxCellVoltageMv!;
    final scale = AntBmsChartScale(minMv: minMv, maxMv: maxMv);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(state: bms),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _Stat(
                label: 'MIN',
                value: '${minMv} mV',
                caption: 'Cell ${bms.minCellIndex}',
                color: _elevated,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Stat(
                label: 'MAX',
                value: '${maxMv} mV',
                caption: 'Cell ${bms.maxCellIndex}',
                color: _balanced,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Stat(
                label: 'DELTA',
                value: '${bms.cellDeltaMv} mV',
                caption: _deltaLabel(bms.cellDeltaMv),
                color: _deltaColor(bms.cellDeltaMv),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('EINZELZELLEN (${bms.cellCount})',
            style: const TextStyle(
                color: Color(0xFF4A5568),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5)),
        const SizedBox(height: 8),
        for (var i = 0; i < bms.cellVoltagesMv.length; i++)
          _CellBar(
            index: i + 1,
            voltageMv: bms.cellVoltagesMv[i],
            minMv: minMv,
            normalized: scale.normalized(bms.cellVoltagesMv[i]),
            isMin: i + 1 == bms.minCellIndex,
            isMax: i + 1 == bms.maxCellIndex,
          ),
        const SizedBox(height: 16),
        Text('TEMPERATUREN',
            style: const TextStyle(
                color: Color(0xFF4A5568),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (var i = 0; i < bms.temperaturesC.length; i++)
              _Chip(
                  label: 'NTC${i + 1}',
                  value: '${bms.temperaturesC[i].toStringAsFixed(1)} °C'),
            _Chip(
                label: 'MOSFET',
                value: '${bms.mosfetTemperatureC.toStringAsFixed(1)} °C'),
            _Chip(
                label: 'BALANCER',
                value: '${bms.balancerTemperatureC.toStringAsFixed(1)} °C'),
          ],
        ),
        const SizedBox(height: 16),
        Text('SCHALTER & STATUS',
            style: const TextStyle(
                color: Color(0xFF4A5568),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _SwitchChip(
              label: 'Entlade-MOSFET',
              status: bms.dischargeMosfetStatus,
              labelFor: AntBmsStatusLabels.dischargeMosfetLabel,
              on: bms.isDischargeMosfetOn,
            ),
            _SwitchChip(
              label: 'Lade-MOSFET',
              status: bms.chargeMosfetStatus,
              labelFor: AntBmsStatusLabels.chargeMosfetLabel,
              on: bms.isChargeMosfetOn,
            ),
            _Chip(
              label: 'Batterie',
              value: AntBmsStatusLabels.batteryStatusLabel(
                  bms.batteryStatusCode ?? 0),
            ),
            _Chip(
              label: 'Balancer',
              value: AntBmsStatusLabels.balancerLabel(bms.balancerStatus),
            ),
            if (bms.sohPercent != null)
              _Chip(label: 'SOH', value: '${bms.sohPercent} %'),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Letzte Aktualisierung: ${_timeLabel(bms.capturedAt)}',
            style: const TextStyle(color: Color(0xFF4A5568), fontSize: 10),
          ),
        ),
      ],
    );
  }

  String _deltaLabel(int deltaMv) {
    if (deltaMv <= 30) return 'Ausgeglichen';
    if (deltaMv <= 100) return 'Leichte Abweichung';
    return 'Kritische Differenz';
  }

  Color _deltaColor(int deltaMv) => switch (cellDeviationForDelta(deltaMv)) {
        CellDeviation.balanced => _balanced,
        CellDeviation.elevated => _elevated,
        CellDeviation.critical => _critical,
      };

  String _timeLabel(DateTime time) {
    final local = time.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}

class _EmptyBms extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111518),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A3548)),
      ),
      child: Column(
        children: const [
          Icon(Icons.battery_unknown, color: Color(0xFF4A5568), size: 40),
          SizedBox(height: 12),
          Text('Kein ANT BMS verbunden',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text(
              'Verbinde ein ANT@BLE-Modul über die Gerätesuche,\num die Einzelzellspannungen anzuzeigen.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Color(0xFF4A5568), fontSize: 12, height: 1.5)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final AntBmsState state;

  const _Header({required this.state});

  @override
  Widget build(BuildContext context) {
    final soc = state.socPercent;
    final color = soc == null
        ? BmsCellMonitor._balanced
        : soc > 50
            ? BmsCellMonitor._balanced
            : soc > 25
                ? BmsCellMonitor._elevated
                : BmsCellMonitor._critical;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111518),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A3548)),
      ),
      child: Row(
        children: [
          Icon(
              state.isCharging
                  ? Icons.battery_charging_full
                  : state.isDischarging
                      ? Icons.bolt
                      : Icons.battery_std,
              color: color,
              size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  soc == null ? '–' : '$soc %',
                  style: TextStyle(
                      color: color,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1.0),
                ),
                const SizedBox(height: 4),
                Text(
                  state.totalVoltageV != null
                      ? '${state.totalVoltageV!.toStringAsFixed(1)} V'
                      : '– V',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
          if (state.currentA != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${state.currentA!.abs().toStringAsFixed(1)} A',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  state.currentA! >= 0 ? 'ENTLADUNG' : 'LADUNG',
                  style: const TextStyle(
                      color: Color(0xFF4A5568),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final Color color;

  const _Stat({
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111518),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3548)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF4A5568),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }
}

class _CellBar extends StatelessWidget {
  final int index;
  final int voltageMv;
  final int minMv;
  final double normalized;
  final bool isMin;
  final bool isMax;

  const _CellBar({
    required this.index,
    required this.voltageMv,
    required this.minMv,
    required this.normalized,
    required this.isMin,
    required this.isMax,
  });

  Color get _color {
    final deviation = voltageMv - minMv;
    return switch (cellDeviationForDelta(deviation)) {
      CellDeviation.balanced => BmsCellMonitor._balanced,
      CellDeviation.elevated => BmsCellMonitor._elevated,
      CellDeviation.critical => BmsCellMonitor._critical,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text('Cell ${index.toString().padLeft(2, '0')}',
                style: const TextStyle(color: Color(0xFF8899AA), fontSize: 11)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(
                    height: 16,
                    color: const Color(0xFF1A2030),
                  ),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: normalized.clamp(0.04, 1.0),
                    child: Container(
                      height: 16,
                      decoration: BoxDecoration(
                        color: _color,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                              color: _color.withOpacity(0.4), blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 74,
            child: Text(
              '${voltageMv} mV${isMax ? ' ▲' : isMin ? ' ▼' : ''}',
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: isMax || isMin ? _color : Colors.white54,
                  fontSize: 11,
                  fontWeight:
                      isMax || isMin ? FontWeight.w700 : FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;

  const _Chip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2030),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A3548)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11),
          children: [
            TextSpan(
                text: '$label: ',
                style: const TextStyle(
                    color: Color(0xFF4A5568),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            TextSpan(text: value, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _SwitchChip extends StatelessWidget {
  final String label;
  final int status;
  final String Function(int) labelFor;
  final bool on;

  const _SwitchChip({
    required this.label,
    required this.status,
    required this.labelFor,
    required this.on,
  });

  @override
  Widget build(BuildContext context) {
    final color = on ? const Color(0xFF39FF14) : const Color(0xFFFF1744);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2030),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text('$label: ${labelFor(status)}',
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}
