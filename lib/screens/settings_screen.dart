import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/l10n/app_strings.dart';

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
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.text(AppText.settings).toUpperCase())),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _SectionTitle(strings.text(AppText.display)),
            SwitchListTile(
              title: Text(strings.text(AppText.imperialUnits)),
              subtitle:
                  Text(useMph ? 'mph / mi' : strings.text(AppText.metricUnits)),
              secondary: const Icon(Icons.straighten),
              value: useMph,
              onChanged: (value) {
                ref.read(_useMphProvider.notifier).state = value;
                storage.setUseMph(value);
              },
            ),
            const SizedBox(height: 20),
            _SectionTitle(strings.text(AppText.connection)),
            ListTile(
              leading: Icon(Icons.bluetooth,
                  color: connected
                      ? const Color(0xFF54E39E)
                      : const Color(0xFFFFB45C)),
              title: Text(connected
                  ? strings.text(AppText.controllerConnected)
                  : strings.text(AppText.notConnected)),
              subtitle: Text(connected
                  ? strings.text(AppText.telemetryActive)
                  : strings.text(AppText.selectController)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pushNamed('/'),
            ),
            if (connected)
              ListTile(
                leading: const Icon(Icons.link_off),
                title: Text(strings.text(AppText.disconnectAction)),
                onTap: () => ref.read(bluetoothServiceProvider).disconnect(),
              ),
            const SizedBox(height: 20),
            _SectionTitle(strings.text(AppText.dataManagement)),
            ListTile(
              leading: const Icon(Icons.dashboard_customize_outlined),
              title: Text(strings.text(AppText.resetDashboard)),
              subtitle: Text(strings.text(AppText.resetDashboardHint)),
              onTap: () => _confirm(
                context,
                title: strings.text(AppText.resetDashboardQuestion),
                message: strings.text(AppText.resetDashboardMessage),
                action: storage.resetDashboardLayout,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.route_outlined),
              title: Text(strings.text(AppText.deleteRides)),
              subtitle: Text(strings.text(AppText.deleteRidesHint)),
              onTap: () => _confirm(
                context,
                title: strings.text(AppText.deleteRidesQuestion),
                message: strings.text(AppText.irreversible),
                action: storage.clearRideSessions,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.layers_clear_outlined),
              title: Text(strings.text(AppText.deleteProfiles)),
              subtitle: Text(strings.text(AppText.deleteProfilesHint)),
              onTap: () => _confirm(
                context,
                title: strings.text(AppText.deleteProfilesQuestion),
                message: strings.text(AppText.deleteProfilesMessage),
                action: storage.clearProfiles,
              ),
            ),
            const SizedBox(height: 20),
            _SectionTitle(strings.text(AppText.safety)),
            ListTile(
              leading: const Icon(Icons.visibility_outlined,
                  color: Color(0xFF54E39E)),
              title: Text(strings.text(AppText.readOnlyActive)),
              subtitle: Text(strings.text(AppText.readOnlyDescription)),
            ),
            const SizedBox(height: 20),
            _SectionTitle(strings.text(AppText.about)),
            ListTile(
              leading: const Icon(Icons.electric_bike_outlined),
              title: const Text('ArcDash 1.0.0 Read-only'),
              subtitle: Text(strings.text(AppText.appDescription)),
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
              child: Text(AppStrings.of(context).text(AppText.cancel))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppStrings.of(context).text(AppText.reset))),
        ],
      ),
    );
    if (confirmed != true) return;
    await action();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppStrings.of(context).text(AppText.dataReset))));
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
