import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/providers/temp_warning_provider.dart';

/// Full-screen temperature warning overlay.
///
/// Rendered as a Stack layer above every cockpit tab. Cold (< 0 °C) shows an
/// amber/blue card including the live fine-grained power limit and the
/// lithium-plating regen warning; hot (> 55 °C) shows a red card advising to
/// pause the ride.
class TempWarningOverlay extends ConsumerWidget {
  const TempWarningOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warn = ref.watch(tempWarningProvider);
    final live = ref.watch(hasLiveTelemetryProvider);
    if (!live || !warn.isActive) return const SizedBox.shrink();

    final isCold = warn.kind == TempWarningKind.tooCold;
    final accent = isCold ? const Color(0xFF38BDF8) : const Color(0xFFFF5252);
    final banner = isCold ? const Color(0xFF0B1B2A) : const Color(0xFF2A0B0B);

    return Positioned.fill(
      child: Material(
        color: Colors.black.withOpacity(0.55),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: banner,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.35),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isCold
                            ? Icons.ac_unit_rounded
                            : Icons.local_fire_department_rounded,
                        color: accent,
                        size: 34,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isCold ? 'AKKU ZU KALT' : 'AKKU ÜBERHITZT',
                          style: TextStyle(
                            color: accent,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    isCold
                        ? 'Hohe Last und Rekuperation können den Akku bei '
                            '${warn.batteryTempC.toStringAsFixed(1)} °C '
                            'dauerhaft schädigen (Lithium-Plating).'
                        : 'Akku-Temperatur '
                            '${warn.batteryTempC.toStringAsFixed(1)} °C. '
                            'Fahrt pausieren und den Akku abkühlen lassen.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  if (isCold) ...[
                    const SizedBox(height: 16),
                    _PowerLimitCard(
                      maxKw: warn.maxPowerKw,
                      percent: warn.availablePercentValue,
                      regenRisky: warn.regenRisky,
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(tempWarningProvider.notifier).dismiss(),
                      icon: const Icon(Icons.visibility_off_outlined, size: 16),
                      label: const Text('5 MIN AUSBLENDEN'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side: BorderSide(color: accent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PowerLimitCard extends StatelessWidget {
  final double maxKw;
  final double percent;
  final bool regenRisky;

  const _PowerLimitCard({
    required this.maxKw,
    required this.percent,
    required this.regenRisky,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MAX LEISTUNG JETZT',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${maxKw.toStringAsFixed(1)} kW',
            style: const TextStyle(
              color: Color(0xFF54E39E),
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            '${percent.toStringAsFixed(0)} % der Nennleistung verfügbar',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
          if (regenRisky) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.bolt, color: Color(0xFFFFB300), size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Rekuperation deaktivieren — Bremsenergie würde als '
                    'Ladestrom in den kalten Akku eingespeist!',
                    style: TextStyle(
                      color: const Color(0xFFFFB300).withOpacity(0.95),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
