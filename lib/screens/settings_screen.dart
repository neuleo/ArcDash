import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';

final _useMphProvider = StateProvider<bool>((ref) {
  return ref.read(storageServiceProvider).useMph;
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useMph = ref.watch(_useMphProvider);
    final connected = ref.watch(isConnectedProvider);
    final storage = ref.read(storageServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('EINSTELLUNGEN')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const _SectionTitle('ANZEIGE'),
            SwitchListTile(
              title: const Text('Imperiale Einheiten'),
              subtitle: Text(useMph ? 'mph und mi' : 'km/h und km'),
              secondary: const Icon(Icons.straighten),
              value: useMph,
              onChanged: (value) {
                ref.read(_useMphProvider.notifier).state = value;
                storage.setUseMph(value);
              },
            ),
            const SizedBox(height: 20),
            const _SectionTitle('VERBINDUNG'),
            ListTile(
              leading: Icon(Icons.bluetooth,
                  color: connected
                      ? const Color(0xFF54E39E)
                      : const Color(0xFFFFB45C)),
              title:
                  Text(connected ? 'Controller verbunden' : 'Nicht verbunden'),
              subtitle: Text(connected
                  ? 'Live-Telemetrie ist aktiv'
                  : 'Controller auswählen oder erneut verbinden'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pushNamed('/'),
            ),
            if (connected)
              ListTile(
                leading: const Icon(Icons.link_off),
                title: const Text('Verbindung trennen'),
                onTap: () => ref.read(bluetoothServiceProvider).disconnect(),
              ),
            const SizedBox(height: 20),
            const _SectionTitle('DATENVERWALTUNG'),
            ListTile(
              leading: const Icon(Icons.dashboard_customize_outlined),
              title: const Text('Dashboard zurücksetzen'),
              subtitle: const Text('Hoch- und Querformat auf Standard setzen'),
              onTap: () => _confirm(
                context,
                title: 'Dashboard zurücksetzen?',
                message: 'Deine angepassten Dashboard-Layouts werden entfernt.',
                action: storage.resetDashboardLayout,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.route_outlined),
              title: const Text('Fahrten löschen'),
              subtitle: const Text('Gespeicherte Sessionhistorie entfernen'),
              onTap: () => _confirm(
                context,
                title: 'Alle Fahrten löschen?',
                message: 'Diese Aktion kann nicht rückgängig gemacht werden.',
                action: storage.clearRideSessions,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.layers_clear_outlined),
              title: const Text('Lokale Profile löschen'),
              subtitle: const Text('Controllerdaten werden nicht verändert'),
              onTap: () => _confirm(
                context,
                title: 'Lokale Profile löschen?',
                message:
                    'Es werden nur lokal gespeicherte Profildateien entfernt.',
                action: storage.clearProfiles,
              ),
            ),
            const SizedBox(height: 20),
            const _SectionTitle('SICHERHEIT'),
            const ListTile(
              leading:
                  Icon(Icons.visibility_outlined, color: Color(0xFF54E39E)),
              title: Text('Read-only-Modus aktiv'),
              subtitle: Text(
                'Diese Version liest Telemetrie und Diagnosedaten. Parameteränderungen und Restore sind deaktiviert.',
              ),
            ),
            const SizedBox(height: 20),
            const _SectionTitle('ÜBER ARCDASH'),
            const ListTile(
              leading: Icon(Icons.electric_bike_outlined),
              title: Text('ArcDash 1.0.0 Read-only'),
              subtitle: Text(
                  'Lokales FarDriver-Cockpit ohne Cloud oder laufende Kosten'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required Future<void> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Zurücksetzen')),
        ],
      ),
    );
    if (confirmed != true) return;
    await action();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Daten wurden zurückgesetzt.')));
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5)),
      );
}
