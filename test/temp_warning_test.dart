import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/ant_bms_state.dart';
import 'package:arcdash/providers/temp_warning_provider.dart';
import 'package:arcdash/widgets/temp_warning_overlay.dart';

class _FakeBmsNotifier extends TempWarningNotifier {
  _FakeBmsNotifier() : super.forTest();
}

// Minimal fakes: tests drive the notifier directly via evaluateForTest,
// so no real service/storage doubles are needed.
class _FakeService {}

class _FakeStorage {}

Widget _wrap(ProviderContainer container, Widget child) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(body: Stack(children: [child])),
    ),
  );
}

/// Creates a container whose tempWarningProvider is backed by an isolated
/// test notifier (no provider wiring), plus the notifier handle itself.
(ProviderContainer, TempWarningNotifier) _makeTestContainer({
  bool live = true,
}) {
  final notifier = TempWarningNotifier.forTest();
  final container = ProviderContainer(overrides: [
    hasLiveTelemetryProvider.overrideWithValue(live),
    tempWarningProvider.overrideWith((ref) => notifier),
  ]);
  return (container, notifier);
}

void main() {
  group('TempWarningNotifier logic', () {
    (ProviderContainer, TempWarningNotifier) make() {
      final notifier = TempWarningNotifier.forTest();
      final container = ProviderContainer(overrides: [
        hasLiveTelemetryProvider.overrideWithValue(true),
        tempWarningProvider.overrideWith((ref) => notifier),
      ]);
      addTearDown(container.dispose);
      return (container, notifier);
    }

    test('no BMS data → no warning', () {
      final (container, notifier) = make();
      notifier.evaluateForTest(null);
      final state = container.read(tempWarningProvider);
      expect(state.kind, TempWarningKind.none);
      expect(state.isActive, isFalse);
    });

    test('-1 °C triggers cold warning with computed power limit', () {
      final (container, notifier) = make();
      final bms = AntBmsState.initial().copyWith(temperaturesC: const [-1.0]);
      notifier.evaluateForTest(bms);
      final state = container.read(tempWarningProvider);
      expect(state.kind, TempWarningKind.tooCold);
      expect(state.isActive, isTrue);
      // 68 % anchor at 0 °C; at -1 °C slightly less: 68 - (13/5) = 65.4 %
      expect(state.availablePercentValue, closeTo(65.4, 0.1));
      expect(state.maxPowerKw, closeTo(12.0 * 0.654, 0.1));
      expect(state.regenRisky, isTrue);
    });

    test('hysteresis keeps cold warning until +2 °C', () {
      final (container, notifier) = make();
      notifier.evaluateForTest(
          AntBmsState.initial().copyWith(temperaturesC: const [-1.0]));
      expect(container.read(tempWarningProvider).kind, TempWarningKind.tooCold);

      // +1 °C: above 0 but below 0+2 hysteresis → still cold
      notifier.evaluateForTest(
          AntBmsState.initial().copyWith(temperaturesC: const [1.0]));
      expect(container.read(tempWarningProvider).kind, TempWarningKind.tooCold);

      // +3 °C: beyond hysteresis → cleared
      notifier.evaluateForTest(
          AntBmsState.initial().copyWith(temperaturesC: const [3.0]));
      expect(container.read(tempWarningProvider).kind, TempWarningKind.none);
    });

    test('56 °C triggers hot warning', () {
      final (container, notifier) = make();
      notifier.evaluateForTest(
          AntBmsState.initial().copyWith(temperaturesC: const [56.0]));
      final state = container.read(tempWarningProvider);
      expect(state.kind, TempWarningKind.tooHot);
      expect(state.isActive, isTrue);
      expect(state.regenRisky, isFalse);
    });

    test('invalid sensor values are ignored', () {
      final (container, notifier) = make();
      notifier.evaluateForTest(
          AntBmsState.initial().copyWith(temperaturesC: const [-999.0]));
      expect(container.read(tempWarningProvider).kind, TempWarningKind.none);
    });

    test('dismiss hides overlay, isActive false', () {
      final (container, notifier) = make();
      notifier.evaluateForTest(
          AntBmsState.initial().copyWith(temperaturesC: const [-5.0]));
      expect(container.read(tempWarningProvider).isActive, isTrue);
      notifier.dismiss();
      expect(container.read(tempWarningProvider).dismissed, isTrue);
      expect(container.read(tempWarningProvider).isActive, isFalse);
    });
  });

  group('TempWarningOverlay widget', () {
    testWidgets('renders cold warning with max kW value', (tester) async {
      final (container, notifier) = _makeTestContainer(live: true);
      addTearDown(container.dispose);
      notifier.evaluateForTest(
          AntBmsState.initial().copyWith(temperaturesC: const [-3.0]));

      await tester.pumpWidget(_wrap(
        container,
        const TempWarningOverlay(),
      ));
      await tester.pump();

      expect(find.text('AKKU ZU KALT'), findsOneWidget);
      expect(find.textContaining('kW'), findsWidgets);
      expect(find.textContaining('Lithium-Plating'), findsOneWidget);
      expect(find.text('5 MIN AUSBLENDEN'), findsOneWidget);
    });

    testWidgets('hidden when no live telemetry', (tester) async {
      final (container, notifier) = _makeTestContainer(live: false);
      addTearDown(container.dispose);
      notifier.evaluateForTest(
          AntBmsState.initial().copyWith(temperaturesC: const [-3.0]));

      await tester.pumpWidget(_wrap(
        container,
        const TempWarningOverlay(),
      ));
      await tester.pump();

      expect(find.text('AKKU ZU KALT'), findsNothing);
    });

    testWidgets('renders hot warning in red variant', (tester) async {
      final (container, notifier) = _makeTestContainer(live: true);
      addTearDown(container.dispose);
      notifier.evaluateForTest(
          AntBmsState.initial().copyWith(temperaturesC: const [58.0]));

      await tester.pumpWidget(_wrap(
        container,
        const TempWarningOverlay(),
      ));
      await tester.pump();

      expect(find.text('AKKU ÜBERHITZT'), findsOneWidget);
      // No power limit card in hot variant
      expect(find.text('MAX LEISTUNG JETZT'), findsNothing);
    });

    testWidgets('nothing rendered when no warning active', (tester) async {
      final (container, notifier) = _makeTestContainer(live: true);
      addTearDown(container.dispose);
      notifier.evaluateForTest(
          AntBmsState.initial().copyWith(temperaturesC: const [22.0]));

      await tester.pumpWidget(_wrap(
        container,
        const TempWarningOverlay(),
      ));
      await tester.pump();

      expect(find.text('AKKU ZU KALT'), findsNothing);
      expect(find.text('AKKU ÜBERHITZT'), findsNothing);
    });
  });
}
