import 'package:flutter/material.dart';
import 'package:arcdash/screens/dashboard_screen.dart';
import 'package:arcdash/screens/settings_screen.dart';
import 'package:arcdash/screens/stats_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.speed), label: 'Cockpit'),
    NavigationDestination(icon: Icon(Icons.route_outlined), label: 'Fahrten'),
    NavigationDestination(
        icon: Icon(Icons.settings_outlined), label: 'Einstellungen'),
  ];

  static const _screens = [
    DashboardScreen(),
    StatsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final useRail = constraints.maxWidth >= 700;
          final content = IndexedStack(
            index: _selectedIndex,
            children: _screens,
          );
          if (useRail) {
            return Scaffold(
              body: SafeArea(
                child: Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _select,
                      labelType: NavigationRailLabelType.all,
                      destinations: _destinations
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
              selectedIndex: _selectedIndex,
              onDestinationSelected: _select,
              destinations: _destinations,
            ),
          );
        },
      );

  void _select(int index) => setState(() => _selectedIndex = index);
}
