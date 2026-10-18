import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/ride_log.dart';
import 'package:arcdash/screens/ride_analysis_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  RideLog createDummyLog() {
    final now = DateTime(2026, 10, 18, 14, 0, 0);
    return RideLog(
      id: 'test_ride_123',
      startedAt: now,
      endedAt: now.add(const Duration(minutes: 5)),
      samples: [
        for (int i = 0; i <= 60; i++)
          RideLogSample(
            t: i,
            speedKph: 20.0 + (i % 25),
            powerKw: 2.0 + (i % 10) * 0.8,
            voltageV: 82.0 - (i * 0.05),
            currentA: 20.0 + (i % 40),
            motorTempC: 35.0 + (i * 0.2),
            controllerTempC: 30.0 + (i * 0.1),
            socPercent: 95.0 - (i * 0.1),
          ),
      ],
    );
  }

  testWidgets(
      'RideAnalysisScreen renders multi-channel selector, presets and chart',
      (tester) async {
    final log = createDummyLog();

    await tester.pumpWidget(MaterialApp(
      home: RideAnalysisScreen(log: log),
    ));
    await tester.pumpAndSettle();

    // Verify Title
    expect(find.text('FAHRT-ANALYSE & TELEMETRIE'), findsOneWidget);

    // Verify Preset Chips
    expect(find.text('Speed'), findsOneWidget);
    expect(find.text('Power & Speed'), findsOneWidget);
    expect(find.text('Thermal / Temps'), findsOneWidget);
    expect(find.text('Battery / Akku'), findsOneWidget);

    // Verify Channel Filter Chips
    expect(find.text('Geschwindigkeit'), findsWidgets);
    expect(find.text('Leistung'), findsWidgets);
    expect(find.text('Spannung (Ctrl)'), findsWidgets);
    expect(find.text('Strom (Ctrl)'), findsWidgets);

    // Tap Preset 'Thermal / Temps'
    await tester.tap(find.text('Thermal / Temps'));
    await tester.pumpAndSettle();

    // Verify thermal section is active in window cards
    expect(find.textContaining('Motortemp'), findsWidgets);
    expect(find.textContaining('Controllertemp'), findsWidgets);

    // Tap a specific filter chip to toggle it
    await tester.tap(find.text('Strom (Ctrl)').first);
    await tester.pumpAndSettle();

    // Stats Table renders
    expect(find.text('ECKWERTE GESAMTE FAHRT'), findsOneWidget);
  });
}
