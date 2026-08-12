import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/widgets/pin_mapping_manager.dart';
import 'package:arcdash/widgets/regen_curve_editor.dart';
import 'package:arcdash/widgets/speed_curve_editor.dart';

void main() {
  group('Curves and Pin Manager Widget Tests', () {
    testWidgets('SpeedCurveEditor renders and triggers callback',
        (tester) async {
      List<int>? updated;
      final ratios = List<int>.filled(18, 100);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpeedCurveEditor(
              ratios: ratios,
              onChanged: (val) => updated = val,
            ),
          ),
        ),
      );

      expect(
          find.text('DREHZAHL-LEISTUNGSKURVE (500–9000 RPM)'), findsOneWidget);
      expect(find.text('100% Full'), findsOneWidget);
      expect(find.text('Linear Ramp'), findsOneWidget);

      await tester.tap(find.text('Linear Ramp'));
      await tester.pump();
      expect(updated, isNotNull);
      expect(updated!.length, 18);
    });

    testWidgets('RegenCurveEditor renders and triggers callback',
        (tester) async {
      List<int>? updated;
      final regen = List<int>.filled(18, -25);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RegenCurveEditor(
              regenRatios: regen,
              onChanged: (val) => updated = val,
            ),
          ),
        ),
      );

      expect(find.text('REKUPERATIONS-KURVE (500–9000 RPM)'), findsOneWidget);
      expect(find.text('Off / Coast (0%)'), findsOneWidget);

      await tester.tap(find.text('Off / Coast (0%)'));
      await tester.pump();
      expect(updated, isNotNull);
      expect(updated!.first, 0);
    });

    testWidgets('PinMappingManager renders pin rows and dropdowns',
        (tester) async {
      String? changedKey;
      int? changedValue;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PinMappingManager(
                pinMappings: const {'boostPin': 13, 'pausePin': 0},
                onChanged: (key, val) {
                  changedKey = key;
                  changedValue = val;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('HARDWARE PIN-BELEGUNG (FUNKTIONSSCHALTER)'),
          findsOneWidget);
      expect(find.text('Boost Mode Pin'), findsOneWidget);
      expect(find.text('Parksperre / Pause Pin (P)'), findsOneWidget);
      expect(changedKey, isNull);
      expect(changedValue, isNull);
    });

    test('TuningProfile serialization preserves 18-point curves and pins', () {
      final profile = TuningProfile.stockOffroad();
      final json = profile.toJson();
      final restored = TuningProfile.fromJson(json);

      expect(restored.name, profile.name);
      expect(restored.speedRatios.length, 18);
      expect(restored.regenRatios.length, 18);
      expect(restored.pinMappings['pausePin'], 0);
    });
  });
}
