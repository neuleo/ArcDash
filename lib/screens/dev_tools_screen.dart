import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/range_prediction_state.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/stats_provider.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:arcdash/services/range_prediction_repository.dart';
import 'package:arcdash/services/diagnostic_log_exporter.dart';

class DevToolsScreen extends ConsumerWidget {
  const DevToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controllerState = ref.watch(controllerProvider);
    final controllerNotifier = ref.watch(controllerProvider.notifier);
    final statsState = ref.watch(statsProvider);
    final learnedProfile = ref.watch(rangePredictionStateProvider);
    final storage = ref.watch(storageServiceProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF080B0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        title: const Text(
          'DEV TOOLS & CONTEXT',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Color(0xFF54E39E)),
            tooltip: 'Gesamtes App-Paket exportieren & teilen',
            onPressed: () => _exportFullContext(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111518),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1A2030)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.developer_mode,
                        color: Color(0xFF00E5FF), size: 32),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Entwickler & Diagnose-Zentrale',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Exportiere den gesamten Zustand der App (Profil, Sessions, Telemetrie, Logs) in einer einzigen Datei für den KI-Manager.',
                            style: TextStyle(
                                color: Color(0xFF8B949E), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons
              const Text('SCHNELLE AKTIONEN',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF123328),
                  foregroundColor: const Color(0xFF54E39E),
                  minimumSize: const Size(double.infinity, 48),
                  alignment: Alignment.centerLeft,
                ),
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Gesamten App-Kontext kopieren (JSON)'),
                onPressed: () => _copyFullContextToClipboard(context, ref),
              ),
              const SizedBox(height: 10),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E2838),
                  foregroundColor: const Color(0xFF00E5FF),
                  minimumSize: const Size(double.infinity, 48),
                  alignment: Alignment.centerLeft,
                ),
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Gesamtes App-Paket importieren'),
                onPressed: () => _importFullContextDialog(context, ref),
              ),
              const SizedBox(height: 20),

              // Overview Status
              const Text('STATUS UBERSICHT',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              _DevStatusCard(
                label: 'Gelerntes Batteriemodell',
                status: learnedProfile != null
                    ? 'Max: ${learnedProfile.maxVoltageV ?? "—"}V | Min: ${learnedProfile.minVoltageV ?? "—"}V'
                    : 'Keine Daten gelernnt',
              ),
              _DevStatusCard(
                label: 'Aktive Session & Historie',
                status:
                    'Fahrten: ${statsState.pastSessions.length} archiviert | Aktuell: ${statsState.currentSession != null ? "${statsState.currentSession!.distanceKm.toStringAsFixed(1)} km" : "Inaktiv"}',
              ),
              _DevStatusCard(
                label: 'Live Telemetrie-Pakete',
                status:
                    'Rate: ${controllerNotifier.packetRate.toStringAsFixed(1)} Hz | Disconnects/Frame-Events: ${controllerNotifier.diagnostics.exportJson().length} chars',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _buildFullContextJson(WidgetRef ref) {
    final controllerState = ref.read(controllerProvider);
    final controllerNotifier = ref.read(controllerProvider.notifier);
    final statsState = ref.read(statsProvider);
    final learnedProfile = ref.read(rangePredictionStateProvider);
    final storage = ref.read(storageServiceProvider);

    return {
      'exportedAt': DateTime.now().toIso8601String(),
      'appVersion': '1.1.0',
      'learnedProfile': learnedProfile?.toJson(),
      'controllerState': {
        'speedKph': controllerState.speedKph,
        'voltageV': controllerState.voltageV,
        'currentA': controllerState.currentA,
        'powerKw': controllerState.powerKw,
        'battCapPercent': controllerState.battCapPercent,
        'rangeKm': controllerState.rangeKm,
        'gear': controllerState.gear,
        'rideMode': controllerState.rideMode.name,
        'motorTempC': controllerState.motorTempC,
        'controllerTempC': controllerState.controllerTempC,
      },
      'activeSession': statsState.currentSession?.toJson(),
      'pastSessions': statsState.pastSessions,
      'diagnosticsLog': controllerNotifier.diagnostics.exportJson(),
      'rawDebugPackets': controllerNotifier.debugPackets,
    };
  }

  void _copyFullContextToClipboard(BuildContext context, WidgetRef ref) {
    final fullJson = _buildFullContextJson(ref);
    final formatted = const JsonEncoder.withIndent('  ').convert(fullJson);
    Clipboard.setData(ClipboardData(text: formatted));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Vollständiger App-Kontext (JSON) in die Zwischenablage kopiert!'),
        backgroundColor: Color(0xFF123328),
      ),
    );
  }

  void _exportFullContext(BuildContext context, WidgetRef ref) {
    final fullJson = _buildFullContextJson(ref);
    final formatted = const JsonEncoder.withIndent('  ').convert(fullJson);
    Clipboard.setData(ClipboardData(text: formatted));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Gesamter App-Zustand zum Teilen kopiert!'),
        backgroundColor: Color(0xFF123328),
      ),
    );
  }

  Future<void> _importFullContextDialog(
      BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0D1117),
        title: const Text('Gesamten App-Kontext importieren',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLines: 8,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'Füge hier das gesammelte App-Kontext-JSON ein...',
            hintStyle: TextStyle(color: Colors.white38),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Importieren'),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(result.trim());
      if (decoded is! Map<String, dynamic>)
        throw const FormatException('Invalid JSON object');

      if (decoded['learnedProfile'] != null) {
        final profile = RangePredictionState.fromJson(
            decoded['learnedProfile'] as Map<String, dynamic>);
        final repo = ref.read(rangePredictionRepositoryProvider);
        repo.saveState(profile);
        ref.invalidate(rangePredictionStateProvider);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('App-Kontext erfolgreich importiert!'),
            backgroundColor: Color(0xFF123328),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Importieren: $e'),
            backgroundColor: const Color(0xFFFF5470),
          ),
        );
      }
    }
  }
}

class _DevStatusCard extends StatelessWidget {
  final String label;
  final String status;

  const _DevStatusCard({required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111518),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1A2030)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Flexible(
            child: Text(
              status,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
