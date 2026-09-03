import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/demo_controller_provider.dart';
import 'package:arcdash/providers/fast_map_provider.dart';
import 'package:arcdash/providers/tuning_provider.dart';

class FastMapScreen extends ConsumerWidget {
  const FastMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fastMapState = ref.watch(fastMapProvider);
    final fastMapNotifier = ref.read(fastMapProvider.notifier);
    final tuningState = ref.watch(tuningProvider);
    final controllerState = ref.watch(effectiveControllerProvider);
    final isConnected = ref.watch(isConnectedProvider);

    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape ||
        MediaQuery.of(context).size.width > MediaQuery.of(context).size.height;

    final isStockActive =
        fastMapState.activeRamMap.toLowerCase().contains('stock') ||
            fastMapState.activeRamMap.toLowerCase().contains('legal');

    return Scaffold(
      backgroundColor: const Color(0xFF080B0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bolt, color: Color(0xFF00E5FF), size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'FAST MAP',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // RAM Volatile Status Hero Banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isStockActive
                      ? const Color(0xFF0A2E1C)
                      : const Color(0xFF0F2636),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isStockActive
                        ? const Color(0xFF00C853)
                        : const Color(0xFF00E5FF),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isStockActive
                              ? const Color(0xFF00C853)
                              : const Color(0xFF00E5FF))
                          .withOpacity(0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isStockActive
                              ? Icons.verified_user_outlined
                              : Icons.speed,
                          color: isStockActive
                              ? const Color(0xFF00C853)
                              : const Color(0xFF00E5FF),
                          size: 26,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'AKTIV IM RAM: ${fastMapState.activeRamMap.toUpperCase()}',
                            style: TextStyle(
                              color: isStockActive
                                  ? const Color(0xFF00C853)
                                  : const Color(0xFF00E5FF),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isStockActive
                          ? 'Drosselung auf 45 km/h aktiv · StVO-konformer Zustand'
                          : 'Volle Leistung im flüchtigen Controller-Speicher aktiv',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.info_outline,
                              color: Colors.white54, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'RAM ist flüchtig: Nach Zündung Aus/Ein startet das Bike automatisch wieder mit dem im Flash gespeicherten Werks-Profil.',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Status message feedback
              if (fastMapState.statusMessage != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF00E5FF).withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: Color(0xFF00E5FF), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fastMapState.statusMessage!,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              if (fastMapState.lastError != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B1219),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.redAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fastMapState.lastError!,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // The 2 Massive 1-Tap Buttons
              isLandscape
                  ? Row(
                      children: [
                        Expanded(
                          child: _buildQuickButton(
                            title: 'STOCK (STREET LEGAL)',
                            subtitle: '45 km/h · StVO konform',
                            icon: Icons.verified_user_outlined,
                            accentColor: const Color(0xFF00C853),
                            isLoading: fastMapState.isApplying,
                            isConnected: isConnected,
                            onPressed: () {
                              HapticFeedback.heavyImpact();
                              fastMapNotifier.applyStockProfile();
                            },
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildQuickButton(
                            title: 'TUNED (OFFEN)',
                            subtitle:
                                'Volle Leistung · ${fastMapState.tunedProfileName}',
                            icon: Icons.bolt,
                            accentColor: const Color(0xFF00E5FF),
                            isLoading: fastMapState.isApplying,
                            isConnected: isConnected,
                            onPressed: () {
                              HapticFeedback.heavyImpact();
                              fastMapNotifier.applyTunedProfile();
                            },
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _buildQuickButton(
                          title: 'STOCK (STREET LEGAL)',
                          subtitle: '45 km/h · StVO konform · Sofort drosseln',
                          icon: Icons.verified_user_outlined,
                          accentColor: const Color(0xFF00C853),
                          isLoading: fastMapState.isApplying,
                          isConnected: isConnected,
                          onPressed: () {
                            HapticFeedback.heavyImpact();
                            fastMapNotifier.applyStockProfile();
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildQuickButton(
                          title: 'TUNED (OFFEN)',
                          subtitle:
                              'Volle Leistung · ${fastMapState.tunedProfileName}',
                          icon: Icons.bolt,
                          accentColor: const Color(0xFF00E5FF),
                          isLoading: fastMapState.isApplying,
                          isConnected: isConnected,
                          onPressed: () {
                            HapticFeedback.heavyImpact();
                            fastMapNotifier.applyTunedProfile();
                          },
                        ),
                      ],
                    ),

              const SizedBox(height: 24),

              // Configuration Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.tune, color: Colors.white70, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'SCHNELLWAHL-EINSTELLUNGEN',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white10, height: 24),

                    // Tuned Profile Dropdown Selector
                    Text(
                      'Zugeordnetes Profil für "TUNED":',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.8), fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B22),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: tuningState.savedProfiles.any((p) =>
                                  p.name == fastMapState.tunedProfileName)
                              ? fastMapState.tunedProfileName
                              : (tuningState.savedProfiles.isNotEmpty
                                  ? tuningState.savedProfiles.first.name
                                  : 'Tuned (Offen)'),
                          isExpanded: true,
                          dropdownColor: const Color(0xFF161B22),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                          items: [
                            DropdownMenuItem(
                              value: 'Tuned (Offen)',
                              child:
                                  const Text('Tuned (Offen) [85 km/h, Sport]'),
                            ),
                            for (final p in tuningState.savedProfiles)
                              if (p.name != 'Tuned (Offen)')
                                DropdownMenuItem(
                                  value: p.name,
                                  child: Text(
                                      '${p.name} (${p.maxSpeedKph.round()} km/h)'),
                                ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              fastMapNotifier.setTunedProfileName(val);
                            }
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Auto-Apply on connect switch
                    Material(
                      color: Colors.transparent,
                      child: SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: const Color(0xFF00E5FF),
                        title: const Text(
                          'Tuned-Profil beim Verbinden automatisch anwenden',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Sobald sich die App mit dem Controller verbindet, wird automatisch 1x das Tuned-Profil in den RAM geschrieben. Beim Ausschalten des Bikes ist es nach dem Neustart wieder legal.',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                        value: fastMapState.autoApplyOnConnect,
                        onChanged: (val) =>
                            fastMapNotifier.setAutoApplyOnConnect(val),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Emergency Panic Reset Button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF5252),
                  side: const BorderSide(color: Color(0x66FF5252)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.warning_amber_rounded, size: 20),
                label: const Text(
                  'PANIK-RESET: SOFORT STREET LEGAL SETZEN',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      fontSize: 12),
                ),
                onPressed: () {
                  HapticFeedback.vibrate();
                  fastMapNotifier.applyStockProfile();
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required bool isLoading,
    required bool isConnected,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF111518),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withOpacity(0.6), width: 2),
            boxShadow: [
              BoxShadow(
                color: accentColor.withOpacity(0.12),
                blurRadius: 10,
                offset: const Offset(0, 3),
              )
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accentColor, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  color: accentColor.withOpacity(0.6), size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
