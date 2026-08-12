import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/tuning_provider.dart';
import 'package:arcdash/services/profile_tools.dart';
import 'package:arcdash/services/write_safety.dart';
import 'package:arcdash/utils/tuning_conversions.dart';

class TuningScreen extends ConsumerWidget {
  const TuningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tuningState = ref.watch(tuningProvider);
    final safety = ref.watch(writeSafetyDecisionProvider);
    final profile = tuningState.pendingProfile;
    final notifier = ref.read(tuningProvider.notifier);
    final isMoving = safety.rejections.contains(SafetyRejection.moving);
    final editorValidation = const ProfileValidator().validateParameters({
      'maxSpeedKph': profile.maxSpeedKph,
      'maxLineCurrA': profile.maxLineCurrA,
      'maxPhaseCurrA': profile.maxPhaseCurrA,
      'regenStrength': profile.regenStrength,
      'throttleResponse': profile.throttleResponse,
    });
    final editorEnabled = editorValidation.valid;

    // Read-back verification (Phase 15, T093): confirmation only appears once
    // the written values are reflected in the ControllerState.
    final controllerState = ref.watch(controllerProvider);
    final expectedSpeedRaw =
        TuningConversions.maxSpeedKphToRaw(profile.maxSpeedKph);
    final expectedLineCurrRaw =
        TuningConversions.maxLineCurrAToRaw(profile.maxLineCurrA);
    final readBackVerified =
        controllerState.maxSpeedRaw == expectedSpeedRaw &&
            controllerState.maxLineCurrRaw == expectedLineCurrRaw;
    final applied = tuningState.appliedSuccessfully;

    return Scaffold(
      backgroundColor: const Color(0xFF080B0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        title: const Text(
          'TUNING',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF1A2030)),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Safety warning banner
              _WarningBanner(decision: safety),
              const SizedBox(height: 20),

              // Presets
              if (!editorEnabled)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFFF9800).withOpacity(0.3)),
                  ),
                  child: const Text(
                    'PROFILE EDITOR LOCKED: hardware limits and verified controller data are required.',
                    style: TextStyle(color: Color(0xFFFF9800), fontSize: 12),
                  ),
                ),
              _SectionHeader(title: 'PRESETS'),
              const SizedBox(height: 10),
              _PresetGrid(
                factoryPresets: TuningProfile.factoryPresets(),
                customPresets: tuningState.savedProfiles,
                selectedName: profile.name,
                onSelect: (p) => notifier.loadPreset(p),
                onDelete: (name) => _confirmDeletePreset(context, ref, name),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showSavePresetDialog(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(
                    '+ NEUES PRESET SPEICHERN',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      fontSize: 12,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00E5FF),
                    side: const BorderSide(color: Color(0xFF2A3548)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Controls
              _SectionHeader(title: 'CONTROLS'),
              const SizedBox(height: 14),

              // Max Speed
              _TuningSlider(
                label: 'Max Speed',
                icon: Icons.speed,
                value: profile.maxSpeedKph,
                min: 10,
                max: 130,
                unit: 'km/h',
                displayValue: profile.maxSpeedKph.toStringAsFixed(0),
                onChanged: editorEnabled
                    ? (kph) => notifier.updateMaxSpeed(kph)
                    : null,
                accentColor: const Color(0xFF00E5FF),
                verified: applied && controllerState.maxSpeedRaw == expectedSpeedRaw,
              ),
              const SizedBox(height: 14),

              // Peak Torque — maps to phase current (20–500 A → 0–100%)
              _TuningSlider(
                label: 'Peak Torque',
                icon: Icons.rotate_right,
                value: (profile.maxPhaseCurrA / 500.0 * 100).clamp(0, 100),
                min: 5,
                max: 100,
                unit: '%',
                displayValue: (profile.maxPhaseCurrA / 500.0 * 100)
                    .clamp(0, 100)
                    .toStringAsFixed(0),
                onChanged: editorEnabled
                    ? (pct) => notifier.updateMaxPhaseCurr(
                        (pct / 100.0 * 500.0).clamp(20, 500))
                    : null,
                accentColor: const Color(0xFF39FF14),
                warningThreshold: 90,
              ),
              const SizedBox(height: 14),

              // Peak Power — maps to line current (10–300 A × 80 V = 0.8–24.0 kW)
              _TuningSlider(
                label: 'Peak Power',
                icon: Icons.electric_bolt,
                value: (profile.maxLineCurrA * 80.0 / 1000.0).clamp(0.8, 25.0),
                min: 0.8,
                max: 25.0,
                unit: 'kW',
                displayValue:
                    (profile.maxLineCurrA * 80.0 / 1000.0).toStringAsFixed(1),
                onChanged: editorEnabled
                    ? (kw) => notifier
                        .updateMaxLineCurr((kw * 1000.0 / 80.0).clamp(10, 300))
                    : null,
                accentColor: const Color(0xFFFF9800),
                warningThreshold: 24.0,
                verified: applied &&
                    controllerState.maxLineCurrRaw == expectedLineCurrRaw,
              ),
              const SizedBox(height: 24),

              // Throttle response
              _SectionHeader(title: 'THROTTLE RESPONSE'),
              const SizedBox(height: 10),
              _ThrottleResponseSelector(
                value: profile.throttleResponse,
                onChanged:
                    editorEnabled ? notifier.updateThrottleResponse : null,
              ),
              const SizedBox(height: 28),

              // Error message
              if (tuningState.lastError != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF1744).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFFF1744).withOpacity(0.3)),
                  ),
                  child: Text(
                    tuningState.lastError!,
                    style: const TextStyle(
                      color: Color(0xFFFF1744),
                      fontSize: 13,
                    ),
                  ),
                ),

              // Success message
              if (tuningState.appliedSuccessfully)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF39FF14).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF39FF14).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Color(0xFF39FF14), size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'Profile applied successfully',
                        style: TextStyle(
                          color: Color(0xFF39FF14),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

              // Apply button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: tuningState.isApplying ||
                          tuningState.isRestoring ||
                          !safety.allowed
                      ? null
                      : () => _showApplyDialog(context, ref, profile),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: const Color(0xFF080B0E),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: const Color(0xFF2A3548),
                  ),
                  child: tuningState.isApplying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF080B0E),
                          ),
                        )
                      : Text(
                          isMoving
                              ? 'STOP BIKE TO APPLY'
                              : 'APPLY TO CONTROLLER',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // Stock HEB restore (Phase 15, T092)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: tuningState.isApplying ||
                          tuningState.isRestoring ||
                          !safety.allowed
                      ? null
                      : () => _showRestoreDialog(context, ref),
                  icon: tuningState.isRestoring
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFFF9800),
                          ),
                        )
                      : const Icon(Icons.restore, size: 18),
                  label: const Text(
                    'WERKSEINSTELLUNGEN WIEDERHERSTELLEN',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      fontSize: 12,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF9800),
                    side: BorderSide(
                        color: const Color(0xFFFF9800).withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              // Read-back verification (Phase 15, T093)
              if (applied)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _ReadBackBanner(verified: readBackVerified),
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showApplyDialog(
      BuildContext context, WidgetRef ref, TuningProfile profile) async {
    final isFullSend = _isExtremeProfile(profile);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111518),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isFullSend
                ? const Color(0xFFFF1744).withOpacity(0.5)
                : const Color(0xFF2A3548),
          ),
        ),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber,
              color: isFullSend
                  ? const Color(0xFFFF1744)
                  : const Color(0xFFFF9800),
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              isFullSend ? 'EXTREME WARNING' : 'APPLY CHANGES?',
              style: TextStyle(
                color: isFullSend ? const Color(0xFFFF1744) : Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isFullSend) ...[
              const Text(
                '⚠ This preset pushes the motor and controller to extreme limits. It can:',
                style: TextStyle(color: Color(0xFFFF1744), fontSize: 13),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Overheat and permanently damage the motor\n'
                '• Void your warranty\n'
                '• Create dangerously high speeds\n'
                '• Be illegal on public roads',
                style: TextStyle(
                    color: Color(0xFFFF9800), fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'Writing to: ${profile.name}\n'
              'Max Speed: ${profile.maxSpeedKph.toStringAsFixed(0)} km/h\n'
              'Peak Torque: ${(profile.maxPhaseCurrA / 400.0 * 100).toStringAsFixed(0)}%\n'
              'Peak Power: ${(profile.maxLineCurrA * 72.0 / 1000.0).toStringAsFixed(1)} kW',
              style: const TextStyle(
                color: Color(0xFF8899AA),
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Changes are written directly to the controller. A stock backup will be preserved.',
              style: TextStyle(
                color: Color(0xFF4A5568),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Color(0xFF4A5568), letterSpacing: 1),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isFullSend
                  ? const Color(0xFFFF1744)
                  : const Color(0xFF00E5FF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              isFullSend ? 'I UNDERSTAND, APPLY' : 'APPLY',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: Color(0xFF080B0E),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      HapticFeedback.heavyImpact();
      await ref.read(tuningProvider.notifier).applyProfile();
    }
  }

  Future<void> _showRestoreDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111518),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: const Color(0xFFFF9800).withOpacity(0.5)),
        ),
        title: const Row(
          children: [
            Icon(Icons.restore, color: Color(0xFFFF9800), size: 22),
            SizedBox(width: 8),
            Text(
              'WERKSRESTORE?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        content: const Text(
          'Alle Parameter werden zurück auf die Werks-Baseline gesetzt '
          '(unmodified_basemap.heb). Das Fahrzeug muss ausgeschaltet und '
          'stillstehen.\n\n'
          'Dieser Vorgang überschreibt dein aktuelles Tuning. Ein Backup '
          'deiner Werte bleibt erhalten.',
          style: TextStyle(color: Color(0xFF8899AA), fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Color(0xFF4A5568), letterSpacing: 1),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: const Color(0xFF080B0E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'WIEDERHERSTELLEN',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: Color(0xFF080B0E),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    HapticFeedback.heavyImpact();
    await ref.read(tuningProvider.notifier).restoreStock();
  }

  Future<void> _showSavePresetDialog(BuildContext context, WidgetRef ref) async {
    final existing = ref
        .read(tuningProvider)
        .savedProfiles
        .map((p) => p.name.toLowerCase())
        .toSet();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _SavePresetDialog(existingNames: existing),
    );
    if (name == null) return;
    HapticFeedback.selectionClick();
    await ref.read(tuningProvider.notifier).saveCurrentProfile(name);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preset "$name" gespeichert')),
      );
    }
  }

  Future<void> _confirmDeletePreset(
      BuildContext context, WidgetRef ref, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111518),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: const Color(0xFFFF1744).withOpacity(0.4)),
        ),
        title: const Text(
          'PRESET LÖSCHEN?',
          style: TextStyle(color: Color(0xFFFF1744), fontSize: 14),
        ),
        content: Text(
          '"$name" wird dauerhaft gelöscht.',
          style: const TextStyle(color: Color(0xFF8899AA), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Color(0xFF4A5568), letterSpacing: 1),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF1744),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'LÖSCHEN',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    HapticFeedback.mediumImpact();
    await ref.read(tuningProvider.notifier).deleteProfile(name);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preset "$name" gelöscht')),
      );
    }
  }
}

/// A preset is treated as "extreme" (extra warning) only when it is a
/// user-created profile pushing beyond factory bounds.
bool _isExtremeProfile(TuningProfile profile) =>
    !profile.isStock &&
    (profile.maxLineCurrA >= 250 || profile.maxSpeedKph > 110.0);

class _WarningBanner extends StatelessWidget {
  final SafetyDecision decision;
  const _WarningBanner({required this.decision});

  @override
  Widget build(BuildContext context) {
    if (!decision.allowed) {
      final moving = decision.rejections.contains(SafetyRejection.moving);
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: (moving ? const Color(0xFFFF1744) : const Color(0xFFFF9800))
              .withOpacity(moving ? 0.12 : 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (moving ? const Color(0xFFFF1744) : const Color(0xFFFF9800))
                .withOpacity(0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(
              moving ? Icons.warning : Icons.lock_outline,
              color: moving ? const Color(0xFFFF1744) : const Color(0xFFFF9800),
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                moving
                    ? 'VEHICLE MOVING — Tuning locked until stationary'
                    : 'TUNING LOCKED — ${describeSafety(decision)}',
                style: TextStyle(
                  color: moving ? const Color(0xFFFF1744) : const Color(0xFFFF9800),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF9800).withOpacity(0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_outlined,
              color: Color(0xFFFF9800), size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Aggressive tuning can overheat the motor, void warranty, or be illegal on public roads. Ride responsibly.',
              style: TextStyle(
                color: Color(0xFFFF9800),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF4A5568),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
      ),
    );
  }
}

class _PresetGrid extends StatelessWidget {
  final List<TuningProfile> factoryPresets;
  final List<TuningProfile> customPresets;
  final String selectedName;
  final ValueChanged<TuningProfile> onSelect;
  final ValueChanged<String> onDelete;

  const _PresetGrid({
    required this.factoryPresets,
    required this.customPresets,
    required this.selectedName,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final presets = [...factoryPresets, ...customPresets];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: presets.map((p) {
        final deletable = customPresets.contains(p);
        return _PresetChip(
          preset: p,
          isSelected: p.name == selectedName,
          deletable: deletable,
          onTap: () {
            HapticFeedback.selectionClick();
            onSelect(p);
          },
          onDelete: deletable ? () => onDelete(p.name) : null,
        );
      }).toList(),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final TuningProfile preset;
  final bool isSelected;
  final bool deletable;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _PresetChip({
    required this.preset,
    required this.isSelected,
    required this.deletable,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = preset.name == 'Custom'
        ? const Color(0xFF8899AA)
        : const Color(0xFF00E5FF);
    final width =
        (preset.name.length * 7.2 + 48).clamp(100.0, 180.0).toDouble();

    return SizedBox(
      width: width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withOpacity(0.15)
                    : const Color(0xFF111518),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? color : const Color(0xFF2A3548),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isSelected) ...[
                    Icon(Icons.check, color: color, size: 12),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      preset.name.toUpperCase(),
                      style: TextStyle(
                        color: isSelected ? color : const Color(0xFF4A5568),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (deletable)
            Positioned(
              right: -5,
              top: -5,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF1744),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TuningSlider extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final String unit;
  final String displayValue;
  final ValueChanged<double>? onChanged;
  final Color accentColor;
  final double? warningThreshold;
  final bool verified;

  const _TuningSlider({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.displayValue,
    required this.onChanged,
    required this.accentColor,
    this.warningThreshold,
    this.verified = false,
  });

  bool get _isWarning => warningThreshold != null && value >= warningThreshold!;

  @override
  Widget build(BuildContext context) {
    final color = _isWarning ? const Color(0xFFFF9800) : accentColor;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111518),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isWarning
              ? const Color(0xFFFF9800).withOpacity(0.35)
              : const Color(0xFF1A2030),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 17),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$displayValue',
                style: TextStyle(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  unit,
                  style: TextStyle(
                    color: color.withOpacity(0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (verified)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Tooltip(
                    message: 'Verifiziert',
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: const Color(0xFF39FF14).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.verified,
                        color: Color(0xFF39FF14),
                        size: 16,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: color,
              inactiveTrackColor: const Color(0xFF1A2030),
              thumbColor: color,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              overlayColor: color.withOpacity(0.15),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged == null
                  ? null
                  : (v) {
                      HapticFeedback.selectionClick();
                      onChanged!(v);
                    },
            ),
          ),
          if (_isWarning)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  const Icon(Icons.warning_amber,
                      color: Color(0xFFFF9800), size: 12),
                  const SizedBox(width: 4),
                  const Text(
                    'High — monitor temps closely',
                    style: TextStyle(
                      color: Color(0xFFFF9800),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ThrottleResponseSelector extends StatelessWidget {
  final int value;
  final ValueChanged<int>? onChanged;

  const _ThrottleResponseSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      (0, 'RACE', const Color(0xFFFF1744)),
      (1, 'SPORT', const Color(0xFFFF9800)),
      (2, 'ECO', const Color(0xFF39FF14)),
    ];

    return Row(
      children: options.map((opt) {
        final (val, label, color) = opt;
        final isSelected = value == val;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: val < 2 ? 8 : 0),
            child: GestureDetector(
              onTap: onChanged == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onChanged!(val);
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withOpacity(0.15)
                      : const Color(0xFF111518),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? color : const Color(0xFF2A3548),
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? color : const Color(0xFF4A5568),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ReadBackBanner extends StatelessWidget {
  final bool verified;

  const _ReadBackBanner({required this.verified});

  @override
  Widget build(BuildContext context) {
    final color =
        verified ? const Color(0xFF39FF14) : const Color(0xFFFF9800);
    final icon = verified ? Icons.verified : Icons.pending_outlined;
    final title = verified ? 'VERIFIZIERT' : 'READ-BACK AUSSTEHEND';
    final subtitle = verified
        ? 'Geschriebene Werte wurden im Controller bestätigt.'
        : 'Warte auf Controller-Bestätigung der geschriebenen Werte…';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style:
                      const TextStyle(color: Color(0xFF4A5568), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SavePresetDialog extends StatefulWidget {
  final Set<String> existingNames;

  const _SavePresetDialog({required this.existingNames});

  @override
  State<_SavePresetDialog> createState() => _SavePresetDialogState();
}

class _SavePresetDialogState extends State<_SavePresetDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Name erforderlich';
    if (widget.existingNames.contains(trimmed.toLowerCase())) {
      return 'Name bereits vergeben';
    }
    return null;
  }

  void _submit() {
    final error = _validate(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111518),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF2A3548)),
      ),
      title: const Text(
        'NEUES PRESET SPEICHERN',
        style: TextStyle(fontSize: 14, letterSpacing: 1.2),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        maxLength: 24,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: 'Preset-Name',
          labelStyle: const TextStyle(color: Color(0xFF8899AA)),
          hintText: 'z. B. Meine Trail-Stufe',
          hintStyle: const TextStyle(color: Color(0xFF4A5568)),
          errorText: _error,
          errorStyle: const TextStyle(color: Color(0xFFFF1744)),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF2A3548)),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF00E5FF)),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'CANCEL',
            style: TextStyle(color: Color(0xFF4A5568), letterSpacing: 1),
          ),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: const Color(0xFF080B0E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            'SPEICHERN',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: Color(0xFF080B0E),
            ),
          ),
        ),
      ],
    );
  }
}
