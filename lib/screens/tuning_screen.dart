import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/tuning_provider.dart';
import 'package:arcdash/services/profile_tools.dart';
import 'package:arcdash/services/write_safety.dart';
import 'package:arcdash/utils/tuning_conversions.dart';
import 'package:arcdash/widgets/pin_mapping_manager.dart';
import 'package:arcdash/widgets/regen_curve_editor.dart';
import 'package:arcdash/widgets/speed_curve_editor.dart';
import 'package:arcdash/widgets/tuning_diff_dialog.dart';

class TuningScreen extends ConsumerStatefulWidget {
  const TuningScreen({super.key});

  @override
  ConsumerState<TuningScreen> createState() => _TuningScreenState();
}

class _TuningScreenState extends ConsumerState<TuningScreen> {
  @override
  Widget build(BuildContext context) {
    final tuningState = ref.watch(tuningProvider);
    final safety = ref.watch(writeSafetyDecisionProvider);
    final profile = tuningState.pendingProfile;
    final notifier = ref.read(tuningProvider.notifier);
    final editorValidation = const ProfileValidator().validateParameters({
      'maxSpeedKph': profile.maxSpeedKph,
      'maxLineCurrA': profile.maxLineCurrA,
      'maxPhaseCurrA': profile.maxPhaseCurrA,
      'regenStrength': profile.regenStrength,
      'throttleResponse': profile.throttleResponse,
    });
    final editorEnabled = editorValidation.valid;

    final controllerState = ref.watch(controllerProvider);
    final expectedSpeedRaw =
        TuningConversions.maxSpeedKphToRaw(profile.maxSpeedKph);
    final expectedLineCurrRaw =
        TuningConversions.maxLineCurrAToRaw(profile.maxLineCurrA);
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
        actions: [
          // Expert Mode Switch
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilterChip(
              label: Text(
                tuningState.expertModeEnabled ? 'EXPERT ON' : 'EXPERT OFF',
                style: TextStyle(
                  color: tuningState.expertModeEnabled
                      ? const Color(0xFFFF9800)
                      : const Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
              selected: tuningState.expertModeEnabled,
              onSelected: (val) {
                if (val) {
                  _showExpertWarningDialog(context, notifier);
                } else {
                  notifier.toggleExpertMode(false);
                }
              },
              backgroundColor: const Color(0xFF1E293B),
              selectedColor: const Color(0xFFFF9800).withValues(alpha: 0.15),
              side: BorderSide(
                color: tuningState.expertModeEnabled
                    ? const Color(0xFFFF9800)
                    : const Color(0xFF334155),
              ),
            ),
          ),
        ],
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
              // Safety Warning Banner
              _WarningBanner(decision: safety),
              const SizedBox(height: 20),

              // Presets Section
              _SectionHeader(
                  title: 'PROFIL-VERWALTUNG (L1E WERKS-BASIS & USER-MAPS)'),
              const SizedBox(height: 10),
              _PresetGrid(
                factoryPresets: TuningProfile.l1ePresets(),
                customPresets: tuningState.savedProfiles,
                selectedName: profile.name,
                onSelect: (p) => notifier.loadPreset(p),
                onDelete: (name) => _confirmDeletePreset(context, ref, name),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      notifier.syncFromController(controllerState, force: true);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Aktuelle Werte vom Controller eingelesen!'),
                          backgroundColor: Color(0xFF123328),
                        ),
                      );
                    },
                    icon: const Icon(Icons.download_for_offline_outlined,
                        size: 16),
                    label: const Text(
                      'VOM CONTROLLER LESEN',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        fontSize: 11,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF54E39E),
                      side: const BorderSide(color: Color(0xFF123328)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _showCloneProfileDialog(context, ref, profile),
                    icon: const Icon(Icons.copy, size: 15),
                    label: const Text(
                      'PROFIL KLONEN',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        fontSize: 11,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00E5FF),
                      side: const BorderSide(color: Color(0xFF2A3548)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  if (!profile.isStock)
                    OutlinedButton.icon(
                      onPressed: () =>
                          _showRenameProfileDialog(context, ref, profile.name),
                      icon: const Icon(Icons.edit, size: 15),
                      label: const Text(
                        'UMBENENNEN',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          fontSize: 11,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Color(0xFF2A3548)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _showSavePresetDialog(context, ref),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text(
                      '+ PRESET SPEICHERN',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        fontSize: 11,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF39FF14),
                      side: const BorderSide(color: Color(0xFF2A3548)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Quick Tuning Bar
              _SectionHeader(title: 'HAUPTLEISTUNG & DYNAMIK (QUICK TUNING)'),
              const SizedBox(height: 14),

              _TuningSlider(
                label: 'Max Speed',
                icon: Icons.speed,
                value: profile.maxSpeedKph,
                min: 10,
                max: 160,
                unit: 'km/h',
                displayValue: profile.maxSpeedKph.toStringAsFixed(0),
                onChanged: editorEnabled
                    ? (kph) => notifier.updateMaxSpeed(kph)
                    : null,
                accentColor: const Color(0xFF00E5FF),
                verified:
                    applied && controllerState.maxSpeedRaw == expectedSpeedRaw,
              ),
              const SizedBox(height: 14),

              _TuningSlider(
                label: 'Peak Torque (Phasenstrom / Drehmoment)',
                icon: Icons.rotate_right,
                value: profile.maxPhaseCurrA,
                min: 20,
                max: 550,
                unit: 'A',
                displayValue: '${profile.maxPhaseCurrA.toStringAsFixed(0)} A',
                onChanged: editorEnabled
                    ? (a) => notifier.updateMaxPhaseCurr(a)
                    : null,
                accentColor: const Color(0xFF39FF14),
                warningThreshold: 500,
              ),
              const SizedBox(height: 14),

              _TuningSlider(
                label: 'Peak Power (Batterie-Dauerstrom)',
                icon: Icons.electric_bolt,
                value: profile.maxLineCurrA,
                min: 10,
                max: 300,
                unit: 'A',
                displayValue:
                    '${profile.maxLineCurrA.toStringAsFixed(0)} A (${(profile.maxLineCurrA * 72 / 1000).toStringAsFixed(1)} kW)',
                onChanged:
                    editorEnabled ? (a) => notifier.updateMaxLineCurr(a) : null,
                accentColor: const Color(0xFFFF9800),
                warningThreshold: 250,
                verified: applied &&
                    controllerState.maxLineCurrRaw == expectedLineCurrRaw,
              ),
              const SizedBox(height: 14),

              _TuningSlider(
                label: 'Boost-Modus Dauer (Timer)',
                icon: Icons.bolt,
                value: profile.boostTimeSeconds.toDouble(),
                min: 0,
                max: 30,
                unit: 's',
                displayValue: '${profile.boostTimeSeconds} s',
                onChanged: editorEnabled
                    ? (s) => notifier.updateBoostTime(s.toInt())
                    : null,
                accentColor: const Color(0xFFFF5470),
              ),
              const SizedBox(height: 24),

              // Throttle Response
              _SectionHeader(title: 'GASANNAHME (THROTTLE RESPONSE)'),
              const SizedBox(height: 10),
              _ThrottleResponseSelector(
                value: profile.throttleResponse,
                onChanged:
                    editorEnabled ? notifier.updateThrottleResponse : null,
              ),
              const SizedBox(height: 24),

              // Mode 1 (DL) & Mode 2 (DM) Scaling
              _SectionHeader(
                  title: 'MODUS 1 (LOW / DL) & MODUS 2 (MEDIUM / DM)'),
              const SizedBox(height: 14),

              _TuningSlider(
                label: 'Modus 1 (LOW / DL) Stromstärke',
                icon: Icons.eco_outlined,
                value: profile.lowSpeedLineCurrPct,
                min: 10,
                max: 100,
                unit: '%',
                displayValue:
                    '${profile.lowSpeedLineCurrPct.toStringAsFixed(0)}%',
                onChanged:
                    editorEnabled ? notifier.updateLowSpeedLineCurr : null,
                accentColor: const Color(0xFF54E39E),
              ),
              const SizedBox(height: 14),

              _TuningSlider(
                label: 'Modus 2 (MEDIUM / DM) Stromstärke',
                icon: Icons.alt_route,
                value: profile.midSpeedLineCurrPct,
                min: 10,
                max: 100,
                unit: '%',
                displayValue:
                    '${profile.midSpeedLineCurrPct.toStringAsFixed(0)}%',
                onChanged:
                    editorEnabled ? notifier.updateMidSpeedLineCurr : null,
                accentColor: const Color(0xFF00E5FF),
              ),
              const SizedBox(height: 24),

              // Accordion 1: 18-Point Speed Curve Editor
              _AccordionSection(
                title: 'DREHZAHL-LEISTUNGSKURVE (500–9000 RPM)',
                icon: Icons.auto_graph,
                accentColor: const Color(0xFF00E5FF),
                child: SpeedCurveEditor(
                  ratios: profile.speedRatios,
                  onChanged: (ratios) => notifier.updateSpeedRatios(ratios),
                  enabled: editorEnabled,
                ),
              ),
              const SizedBox(height: 14),

              // Accordion 2: 18-Point Regen Curve Editor
              _AccordionSection(
                title: 'REKUPERATIONS-KURVE & MOTORBREMSE',
                icon: Icons.bolt,
                accentColor: const Color(0xFF39FF14),
                child: RegenCurveEditor(
                  regenRatios: profile.regenRatios,
                  onChanged: (regen) => notifier.updateRegenRatios(regen),
                  enabled: editorEnabled,
                ),
              ),
              const SizedBox(height: 14),

              // Accordion 3: Pin Mapping Manager
              _AccordionSection(
                title: 'HARDWARE-PINS & FUNKTIONSSCHALTER',
                icon: Icons.cable,
                accentColor: const Color(0xFFFF9800),
                child: PinMappingManager(
                  pinMappings: profile.pinMappings,
                  onChanged: (key, val) => notifier.updatePinMapping(key, val),
                  enabled: editorEnabled && tuningState.expertModeEnabled,
                ),
              ),
              const SizedBox(height: 14),

              // Accordion 4: Protection & Cutoffs
              _AccordionSection(
                title: 'SCHUTZGRENZEN & ABSCHALTUNGEN (VOLTAGE & TEMPS)',
                icon: Icons.shield,
                accentColor: const Color(0xFFFF5470),
                child: Column(
                  children: [
                    _TuningSlider(
                      label: 'Unterspannungsabschaltung (LVC)',
                      icon: Icons.battery_alert,
                      value: profile.lowVoltCutoffV,
                      min: 45,
                      max: 85,
                      unit: 'V',
                      displayValue:
                          '${profile.lowVoltCutoffV.toStringAsFixed(1)} V',
                      onChanged:
                          editorEnabled ? notifier.updateLowVoltCutoff : null,
                      accentColor: const Color(0xFFFF5470),
                    ),
                    const SizedBox(height: 12),
                    _TuningSlider(
                      label: 'Überspannungsschutz (OVP)',
                      icon: Icons.flash_on,
                      value: profile.overVoltCutoffV,
                      min: 75,
                      max: 105,
                      unit: 'V',
                      displayValue:
                          '${profile.overVoltCutoffV.toStringAsFixed(1)} V',
                      onChanged:
                          editorEnabled ? notifier.updateOverVoltCutoff : null,
                      accentColor: const Color(0xFFFF5470),
                    ),
                    const SizedBox(height: 12),
                    _TuningSlider(
                      label: 'Motor-Temperaturschutz',
                      icon: Icons.thermostat,
                      value: profile.motorTempLimitC,
                      min: 80,
                      max: 150,
                      unit: '°C',
                      displayValue:
                          '${profile.motorTempLimitC.toStringAsFixed(0)} °C',
                      onChanged:
                          editorEnabled ? notifier.updateMotorTempLimit : null,
                      accentColor: const Color(0xFFFF9800),
                    ),
                    const SizedBox(height: 12),
                    _TuningSlider(
                      label: 'Controller-Temperaturschutz',
                      icon: Icons.device_thermostat,
                      value: profile.controllerTempLimitC,
                      min: 60,
                      max: 115,
                      unit: '°C',
                      displayValue:
                          '${profile.controllerTempLimitC.toStringAsFixed(0)} °C',
                      onChanged: editorEnabled
                          ? notifier.updateControllerTempLimit
                          : null,
                      accentColor: const Color(0xFFFF9800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Apply & Restore Buttons
              if (applied)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF39FF14).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF39FF14).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Color(0xFF39FF14), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tuningState.lastAppliedWasFlash
                              ? 'IN FLASH GESPEICHERT & VERIFIZIERT (DAUERHAFT)'
                              : 'IN RAM GESCHRIEBEN (TEMPORÄR - RESET BEI BOOT)',
                          style: const TextStyle(
                              color: Color(0xFF39FF14),
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),

              // The 2 Distinct Write Buttons: RAM vs Flash
              Row(
                children: [
                  // Button 1: Auf RAM schreiben (Sofort aktiv, flüchtig)
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      onPressed: safety.allowed && !tuningState.isApplying
                          ? () => _applyToRamImmediately(context, notifier)
                          : null,
                      icon:
                          tuningState.isApplying && !tuningState.isSavingToFlash
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(Icons.memory, size: 20),
                      label: Text(
                        tuningState.isApplying && !tuningState.isSavingToFlash
                            ? 'SCHREIBE IN RAM...'
                            : 'AUF RAM SCHREIBEN',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          fontSize: 12,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: const Color(0xFF1E293B),
                        disabledForegroundColor: const Color(0xFF475569),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Button 2: Save to Flash (Mit Bestätigungsdialog, dauerhaft)
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: safety.allowed && !tuningState.isApplying
                          ? () =>
                              _confirmSaveToFlash(context, notifier, profile)
                          : null,
                      icon:
                          tuningState.isApplying && tuningState.isSavingToFlash
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFFFB300),
                                  ),
                                )
                              : const Icon(Icons.save, size: 18),
                      label: Text(
                        tuningState.isApplying && tuningState.isSavingToFlash
                            ? 'SPEICHERE...'
                            : 'IN FLASH',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          fontSize: 12,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFFB300),
                        side: const BorderSide(color: Color(0xFFFFB300)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Werks-Restore
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: safety.allowed && !tuningState.isRestoring
                      ? () => _confirmRestore(context, notifier)
                      : null,
                  icon: const Icon(Icons.restore,
                      color: Color(0xFFFF5470), size: 18),
                  label: const Text(
                    'WERKSEINSTELLUNGEN WIEDERHERSTELLEN (.HEB BASEMAP)',
                    style: TextStyle(
                      color: Color(0xFFFF5470),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _applyToRamImmediately(BuildContext context, TuningNotifier notifier) {
    HapticFeedback.selectionClick();
    notifier.applyProfile(saveToFlash: false);
  }

  void _confirmSaveToFlash(
      BuildContext context, TuningNotifier notifier, TuningProfile profile) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: Row(
          children: const [
            Icon(Icons.save, color: Color(0xFFFFB300)),
            SizedBox(width: 8),
            Text('IN FLASH SPEICHERN?',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Text(
          'Möchtest du das Profil "${profile.name}" wirklich DAUERHAFT in den internen Festspeicher (Flash/EEPROM) des FarDriver Controllers brennen?\n\n'
          '⚠️ ACHTUNG: Das Bike startet nach dem Aus- und Einschalten dann standardmäßig immer mit diesen Werten.\n\n'
          'Empfehlung: Als Standard-Flash das ungedrosselte/gedrosselte Profil festlegen und Tuning-Maps nur bei Bedarf in den RAM schreiben.',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('ABBRECHEN', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.applyProfile(saveToFlash: true);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB300)),
            child: const Text('JA, IN FLASH SPEICHERN',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showCloneProfileDialog(
      BuildContext context, WidgetRef ref, TuningProfile source) {
    final controller = TextEditingController(text: '${source.name} (Kopie)');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('PROFIL KLONEN',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Neuer Profil-Name',
            hintStyle: TextStyle(color: Color(0xFF64748B)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('ABBRECHEN', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(tuningProvider.notifier).cloneProfile(source, name);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Profil "$name" erfolgreich geklont!'),
                    backgroundColor: const Color(0xFF123328),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF)),
            child: const Text('KLONEN',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showRenameProfileDialog(
      BuildContext context, WidgetRef ref, String oldName) {
    final controller = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('PROFIL UMBENENNEN',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Neuer Profil-Name',
            hintStyle: TextStyle(color: Color(0xFF64748B)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('ABBRECHEN', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(tuningProvider.notifier).renameProfile(oldName, name);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF)),
            child: const Text('UMBENENNEN',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDiffDialog(BuildContext context, TuningNotifier notifier,
      TuningProfile pendingProfile) {
    showDialog(
      context: context,
      builder: (ctx) => TuningDiffDialog(
        originalProfile: TuningProfile.stockOffroad(),
        pendingProfile: pendingProfile,
        onConfirm: () => notifier.applyProfile(),
      ),
    );
  }

  void _showExpertWarningDialog(BuildContext context, TuningNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: Row(
          children: const [
            Icon(Icons.warning, color: Color(0xFFFF9800)),
            SizedBox(width: 8),
            Text('EXPERTMAP FREISCHALTEN',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: const Text(
          'Der Experten-Modus erlaubt das Verändern hardwarekritischer Parameter wie Pin-Mappings, Polpaare und Kalibrierungen.\n\nFehlerhafte Werte können den Motor oder Controller beschädigen. Bitte nur mit Fachkenntnis anpassen.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('ABBRECHEN', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () {
              notifier.toggleExpertMode(true);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800)),
            child: const Text('FREISCHALTEN',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmRestore(BuildContext context, TuningNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('WERKSEINSTELLUNGEN WIEDERHERSTELLEN?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          'Alle 156 Register werden atomar aus der "unmodified_basemap.heb" zurückgeschrieben.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('ABBRECHEN', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.restoreStock();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5470)),
            child: const Text('RESTORE STARTEN',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSavePresetDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('PRESET SPEICHERN',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Preset Name (z.B. Mein Trail)',
            hintStyle: TextStyle(color: Color(0xFF64748B)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('ABBRECHEN', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(tuningProvider.notifier).saveCurrentProfile(name);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF)),
            child: const Text('SPEICHERN',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDeletePreset(BuildContext context, WidgetRef ref, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: Text('PRESET "$name" LÖSCHEN?',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('ABBRECHEN', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(tuningProvider.notifier).deleteProfile(name);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5470)),
            child: const Text('LÖSCHEN',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final SafetyDecision decision;

  const _WarningBanner({required this.decision});

  @override
  Widget build(BuildContext context) {
    if (decision.allowed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF39FF14).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: const Color(0xFF39FF14).withValues(alpha: 0.25)),
        ),
        child: Row(
          children: const [
            Icon(Icons.check_circle_outline,
                color: Color(0xFF39FF14), size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'SCHREIBENGINE BEREIT (Fahrzeug steht still, Telemetrie aktiv)',
                style: TextStyle(
                    color: Color(0xFF39FF14),
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5470).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: const Color(0xFFFF5470).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: Color(0xFFFF5470), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'SCHREIBEN GESPERRT: ${describeSafety(decision)}',
              style: const TextStyle(
                  color: Color(0xFFFF5470),
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
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
        color: Color(0xFF64748B),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 2,
      ),
    );
  }
}

class _AccordionSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final Widget child;

  const _AccordionSection({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0F172A),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            leading: Icon(icon, color: accentColor, size: 20),
            title: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            childrenPadding: const EdgeInsets.all(14),
            children: [child],
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    final isWarning = warningThreshold != null && value >= warningThreshold!;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isWarning
                ? const Color(0xFFFF5470).withValues(alpha: 0.5)
                : const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(icon, color: accentColor, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (verified)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child:
                          Icon(Icons.check, color: Color(0xFF39FF14), size: 14),
                    ),
                  Text(
                    displayValue,
                    style: TextStyle(
                      color: isWarning ? const Color(0xFFFF5470) : accentColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor:
                  isWarning ? const Color(0xFFFF5470) : accentColor,
              inactiveTrackColor: const Color(0xFF1E293B),
              thumbColor: isWarning ? const Color(0xFFFF5470) : accentColor,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayColor: accentColor.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
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
    final allPresets = [...factoryPresets, ...customPresets];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: allPresets.map((preset) {
        final isSelected = preset.name == selectedName;
        return InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onSelect(preset);
          },
          onLongPress: !preset.isStock ? () => onDelete(preset.name) : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF39FF14).withValues(alpha: 0.12)
                  : const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF39FF14)
                    : const Color(0xFF1E293B),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Text(
              preset.name,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xFF39FF14)
                    : const Color(0xFFCBD5E1),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
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
    const modes = [
      (id: 0, label: 'Line / Race', desc: 'Direkt & Aggressiv'),
      (id: 1, label: 'Sport', desc: 'Linear & Berechenbar'),
      (id: 2, label: 'ECO', desc: 'Sanft & Sparsam'),
    ];

    return Row(
      children: modes.map((m) {
        final isSelected = value == m.id;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: onChanged != null ? () => onChanged!(m.id) : null,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF00E5FF).withValues(alpha: 0.15)
                      : const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF00E5FF)
                        : const Color(0xFF1E293B),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      m.label,
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFF00E5FF)
                            : const Color(0xFFCBD5E1),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m.desc,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
