import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/widgets/tuning_diff_dialog.dart';

void main() {
  group('TuningDiffDialog Widget Tests', () {
    testWidgets('renders diff dialog with changed parameters and risk badges',
        (tester) async {
      bool confirmed = false;
      final stock = TuningProfile.stockOffroad();
      final custom = stock.copyWith(
        maxSpeedKph: 85,
        maxLineCurrA: 180,
        maxPhaseCurrA: 400,
        regenStrength: 0.45,
      );

      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TuningDiffDialog(
              originalProfile: stock,
              pendingProfile: custom,
              onConfirm: () {
                confirmed = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('PARAMETER-DIFF INSPEKTOR'), findsOneWidget);
      expect(find.text('Höchstgeschwindigkeit (Max Speed)'), findsOneWidget);
      expect(find.text('Batterie-Dauerstrom (Line Current)'), findsOneWidget);
      expect(find.text('Max. Phasenstrom (Peak Torque)'), findsOneWidget);

      expect(find.text('KRITISCH'), findsNWidgets(2)); // Line & Phase Current
      expect(find.text('PERFORMANCE'), findsOneWidget); // Speed
      expect(find.text('KOMFORT'), findsOneWidget); // Regen

      await tester.tap(find.text('VERIFIZIERT SCHREIBEN'));
      await tester.pumpAndSettle();

      expect(confirmed, isTrue);
    });

    testWidgets('cancels dialog when tapping ABBRECHEN without confirming',
        (tester) async {
      bool confirmed = false;
      final stock = TuningProfile.stockOffroad();
      final custom = stock.copyWith(maxSpeedKph: 60);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => TuningDiffDialog(
                      originalProfile: stock,
                      pendingProfile: custom,
                      onConfirm: () {
                        confirmed = true;
                      },
                    ),
                  );
                },
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      expect(find.text('PARAMETER-DIFF INSPEKTOR'), findsOneWidget);

      await tester.tap(find.text('ABBRECHEN'));
      await tester.pumpAndSettle();

      expect(find.text('PARAMETER-DIFF INSPEKTOR'), findsNothing);
      expect(confirmed, isFalse);
    });
  });
}
