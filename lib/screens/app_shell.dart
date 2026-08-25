import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/screens/dashboard_screen.dart';
import 'package:arcdash/screens/map_screen.dart';
import 'package:arcdash/screens/settings_screen.dart';
import 'package:arcdash/screens/stats_screen.dart';
import 'package:arcdash/screens/tuning_screen.dart';
import 'package:arcdash/l10n/app_strings.dart';

final appShellIndexProvider = StateProvider<int>((ref) => 0);

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _screens = [
    DashboardScreen(),
    TuningScreen(),
    StatsScreen(),
    MapScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(appShellIndexProvider);
    final strings = AppStrings.of(context);

    final destinations = [
      NavigationDestination(
          icon: const Icon(Icons.speed), label: strings.text(AppText.cockpit)),
      NavigationDestination(
          icon: const Icon(Icons.tune), label: strings.text(AppText.tuning)),
      NavigationDestination(
          icon: const Icon(Icons.route_outlined),
          label: strings.text(AppText.rides)),
      NavigationDestination(
          icon: const Icon(Icons.map_outlined),
          label: strings.text(AppText.navigationTab)),
      NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          label: strings.text(AppText.settings)),
    ];

    final content = IndexedStack(
      index: selectedIndex,
      children: _screens,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 700;

        if (useRail) {
          return Scaffold(
            key: _scaffoldKey,
            drawer: Drawer(
              backgroundColor: const Color(0xFF0D1117),
              child: SafeArea(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.bolt,
                                color: Color(0xFF00E5FF), size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'ARCDASH',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white10),
                    for (int i = 0; i < destinations.length; i++)
                      ListTile(
                        leading: Icon(
                          switch (i) {
                            0 => Icons.speed,
                            1 => Icons.tune,
                            2 => Icons.route_outlined,
                            3 => Icons.map_outlined,
                            _ => Icons.settings_outlined,
                          },
                          color: selectedIndex == i
                              ? const Color(0xFF00E5FF)
                              : Colors.white54,
                        ),
                        title: Text(
                          destinations[i].label,
                          style: TextStyle(
                            color: selectedIndex == i
                                ? const Color(0xFF00E5FF)
                                : Colors.white,
                            fontWeight: selectedIndex == i
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        selected: selectedIndex == i,
                        selectedTileColor:
                            const Color(0xFF00E5FF).withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        onTap: () {
                          ref.read(appShellIndexProvider.notifier).state = i;
                          Navigator.pop(context);
                        },
                      ),
                  ],
                ),
              ),
            ),
            body: SafeArea(
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: (i) =>
                        ref.read(appShellIndexProvider.notifier).state = i,
                    labelType: NavigationRailLabelType.all,
                    destinations: destinations
                        .map((destination) => NavigationRailDestination(
                              icon: destination.icon,
                              selectedIcon: destination.selectedIcon,
                              label: Text(destination.label),
                            ))
                        .toList(),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          body: content,
          bottomNavigationBar: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: (i) =>
                ref.read(appShellIndexProvider.notifier).state = i,
            destinations: destinations,
          ),
        );
      },
    );
  }
}
