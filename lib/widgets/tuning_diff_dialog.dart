import 'package:flutter/material.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/services/write_safety.dart';

class TuningDiffItem {
  final String label;
  final String category;
  final IconData icon;
  final String oldValue;
  final String newValue;
  final ParameterRisk risk;

  const TuningDiffItem({
    required this.label,
    required this.category,
    required this.icon,
    required this.oldValue,
    required this.newValue,
    required this.risk,
  });
}

class TuningDiffDialog extends StatelessWidget {
  final TuningProfile originalProfile;
  final TuningProfile pendingProfile;
  final VoidCallback onConfirm;

  const TuningDiffDialog({
    super.key,
    required this.originalProfile,
    required this.pendingProfile,
    required this.onConfirm,
  });

  List<TuningDiffItem> _calculateDiffs() {
    final diffs = <TuningDiffItem>[];

    if (originalProfile.maxSpeedKph != pendingProfile.maxSpeedKph) {
      diffs.add(TuningDiffItem(
        label: 'Höchstgeschwindigkeit (Max Speed)',
        category: 'Motor & Dynamik',
        icon: Icons.speed,
        oldValue: '${originalProfile.maxSpeedKph.toStringAsFixed(0)} km/h',
        newValue: '${pendingProfile.maxSpeedKph.toStringAsFixed(0)} km/h',
        risk: ParameterRisk.performance,
      ));
    }

    if (originalProfile.maxLineCurrA != pendingProfile.maxLineCurrA) {
      diffs.add(TuningDiffItem(
        label: 'Batterie-Dauerstrom (Line Current)',
        category: 'Motor & Dynamik',
        icon: Icons.bolt,
        oldValue: '${originalProfile.maxLineCurrA.toStringAsFixed(0)} A',
        newValue: '${pendingProfile.maxLineCurrA.toStringAsFixed(0)} A',
        risk: ParameterRisk.safetyCritical,
      ));
    }

    if (originalProfile.maxPhaseCurrA != pendingProfile.maxPhaseCurrA) {
      diffs.add(TuningDiffItem(
        label: 'Max. Phasenstrom (Peak Torque)',
        category: 'Motor & Dynamik',
        icon: Icons.offline_bolt,
        oldValue: '${originalProfile.maxPhaseCurrA.toStringAsFixed(0)} A',
        newValue: '${pendingProfile.maxPhaseCurrA.toStringAsFixed(0)} A',
        risk: ParameterRisk.safetyCritical,
      ));
    }

    if (originalProfile.regenStrength != pendingProfile.regenStrength) {
      final oldPct = originalProfile.regenStrength <= 1.0
          ? originalProfile.regenStrength * 100
          : originalProfile.regenStrength;
      final newPct = pendingProfile.regenStrength <= 1.0
          ? pendingProfile.regenStrength * 100
          : pendingProfile.regenStrength;
      diffs.add(TuningDiffItem(
        label: 'Rekuperation / Bremskraft',
        category: 'Rekuperation',
        icon: Icons.battery_charging_full,
        oldValue: '${oldPct.toStringAsFixed(0)} %',
        newValue: '${newPct.toStringAsFixed(0)} %',
        risk: ParameterRisk.comfort,
      ));
    }

    if (originalProfile.throttleResponse != pendingProfile.throttleResponse) {
      final modeNames = {1: 'Sport', 2: 'ECO', 3: 'Soft / Custom'};
      diffs.add(TuningDiffItem(
        label: 'Gasannahme / Kennlinie',
        category: 'Fahrmodus',
        icon: Icons.tune,
        oldValue: modeNames[originalProfile.throttleResponse] ??
            '${originalProfile.throttleResponse}',
        newValue: modeNames[pendingProfile.throttleResponse] ??
            '${pendingProfile.throttleResponse}',
        risk: ParameterRisk.comfort,
      ));
    }

    // Speed curve diff
    int speedCurveChanges = 0;
    for (int i = 0;
        i < originalProfile.speedRatios.length &&
            i < pendingProfile.speedRatios.length;
        i++) {
      if ((originalProfile.speedRatios[i] - pendingProfile.speedRatios[i])
              .abs() >
          0) {
        speedCurveChanges++;
      }
    }
    if (speedCurveChanges > 0) {
      diffs.add(TuningDiffItem(
        label: '18-Punkte Drehzahlkurve (500–9000 RPM)',
        category: 'Kennlinien',
        icon: Icons.show_chart,
        oldValue: 'Original-Kurve',
        newValue: '$speedCurveChanges Stützpunkte angepasst',
        risk: ParameterRisk.performance,
      ));
    }

    // Regen curve diff
    int regenCurveChanges = 0;
    for (int i = 0;
        i < originalProfile.regenRatios.length &&
            i < pendingProfile.regenRatios.length;
        i++) {
      if ((originalProfile.regenRatios[i] - pendingProfile.regenRatios[i])
              .abs() >
          0) {
        regenCurveChanges++;
      }
    }
    if (regenCurveChanges > 0) {
      diffs.add(TuningDiffItem(
        label: '18-Punkte Rekuperationskurve',
        category: 'Kennlinien',
        icon: Icons.ssid_chart,
        oldValue: 'Original-Kurve',
        newValue: '$regenCurveChanges Stützpunkte angepasst',
        risk: ParameterRisk.comfort,
      ));
    }

    // Pin mappings diff
    int pinChanges = 0;
    originalProfile.pinMappings.forEach((key, value) {
      if (pendingProfile.pinMappings[key] != value) pinChanges++;
    });
    if (pinChanges > 0) {
      diffs.add(TuningDiffItem(
        label: 'Hardware Pin-Belegung',
        category: 'Hardware',
        icon: Icons.settings_input_component,
        oldValue: 'Aktuelle Pins',
        newValue: '$pinChanges Pin-Funktionen geändert',
        risk: ParameterRisk.hardware,
      ));
    }

    return diffs;
  }

  @override
  Widget build(BuildContext context) {
    final diffs = _calculateDiffs();
    final hasCritical = diffs.any((d) =>
        d.risk == ParameterRisk.safetyCritical ||
        d.risk == ParameterRisk.hardware);

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: hasCritical
              ? const Color(0xFFFF5470).withValues(alpha: 0.6)
              : const Color(0xFF00E5FF).withValues(alpha: 0.3),
        ),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 650),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: hasCritical
                        ? const Color(0xFFFF5470).withValues(alpha: 0.15)
                        : const Color(0xFF00E5FF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    hasCritical
                        ? Icons.warning_amber_rounded
                        : Icons.find_in_page,
                    color: hasCritical
                        ? const Color(0xFFFF5470)
                        : const Color(0xFF00E5FF),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PARAMETER-DIFF INSPEKTOR',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Zielprofil: ${pendingProfile.name}',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close,
                      color: Color(0xFF64748B), size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Safety & Summary Banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user,
                      color: Color(0xFF39FF14), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      diffs.isEmpty
                          ? 'Keine veränderten Parameter erkannt.'
                          : '${diffs.length} geänderte Parameter vor dem Schreiben geprüft.',
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Diff List
            Expanded(
              child: diffs.isEmpty
                  ? const Center(
                      child: Text(
                        'Das Profil entspricht den aktuellen Controller-Werten.',
                        style:
                            TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      ),
                    )
                  : ListView.separated(
                      itemCount: diffs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = diffs[index];
                        return _buildDiffCard(item);
                      },
                    ),
            ),
            const SizedBox(height: 16),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF94A3B8),
                      side: const BorderSide(color: Color(0xFF334155)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('ABBRECHEN'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: diffs.isEmpty
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            onConfirm();
                          },
                    icon: const Icon(Icons.security_update_good, size: 18),
                    label: const Text(
                      'VERIFIZIERT SCHREIBEN',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF39FF14),
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: const Color(0xFF1E293B),
                      disabledForegroundColor: const Color(0xFF475569),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiffCard(TuningDiffItem item) {
    Color riskColor;
    String riskLabel;

    switch (item.risk) {
      case ParameterRisk.safetyCritical:
      case ParameterRisk.hardware:
        riskColor = const Color(0xFFFF5470);
        riskLabel = 'KRITISCH';
        break;
      case ParameterRisk.performance:
        riskColor = const Color(0xFF00E5FF);
        riskLabel = 'PERFORMANCE';
        break;
      case ParameterRisk.comfort:
        riskColor = const Color(0xFF39FF14);
        riskLabel = 'KOMFORT';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161E2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF26334D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(item.icon, color: riskColor, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.label,
                  style: const TextStyle(
                    color: Color(0xFFF1F5F9),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: riskColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: riskColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  riskLabel,
                  style: TextStyle(
                    color: riskColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  item.oldValue,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_rounded,
                  color: Color(0xFF00E5FF), size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.newValue,
                  style: TextStyle(
                    color: riskColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
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
