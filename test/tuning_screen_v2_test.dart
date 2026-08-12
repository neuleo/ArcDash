import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/tuning_provider.dart';
import 'package:arcdash/screens/tuning_screen.dart';
import 'package:arcdash/services/write_safety.dart';
import 'package:arcdash/utils/crc_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tuning_v2_test.dart' as t2;

/// Builds a valid 16-byte FarDriver status frame.
List<int> _statusPacket(int id, List<int> rawData) {
  final packet = List<int>.filled(16, 0);
  packet[0] = 0xAA;
  packet[1] = id;
  for (var i = 0; i < rawData.length && i < 12; i++) {
    packet[i + 2] = rawData[i];
  }
  CrcCalculator.computeCRC(packet, 16);
  return packet;
}

Future<void> _settleConnect(
    WidgetTester tester, t2.FakeDongleService dongle) async {
  await tester.pump(const Duration(milliseconds: 600));
  dongle.emit(_statusPacket(0, List<int>.filled(12, 0)));
  await tester.pump(const Duration(seconds: 3));
}

const _allowedSafety = SafetyDecision(allowed: true, rejections: {});

(ProviderContainer, Widget) _buildSession({
  required t2.FakeDongleService dongle,
  required t2.MemoryStorage storage,
  List<Override> extra = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      bluetoothServiceProvider.overrideWithValue(dongle),
      storageServiceProvider.overrideWithValue(storage),
      ...extra,
    ],
  );
  return (
    container,
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: TuningScreen()),
    ),
  );
}

void main() {
  group('Tuning Screen Presets and UI', () {
    testWidgets('lists factory presets and saves custom presets',
        (tester) async {
      final storage = t2.MemoryStorage();
      await storage
          .saveProfile(TuningProfile.custom().copyWith(name: 'My Trail'));
      final dongle = t2.FakeDongleService();
      final (container, widget) =
          _buildSession(dongle: dongle, storage: storage);
      addTearDown(container.dispose);

      await tester.pumpWidget(widget);
      await _settleConnect(tester, dongle);

      expect(find.text('Stock Offroad'), findsOneWidget);
      expect(find.text('Eco Range'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('My Trail'), findsOneWidget);
      expect(find.text('+ NEUES PRESET SPEICHERN'), findsOneWidget);
      expect(find.text('WERKSEINSTELLUNGEN WIEDERHERSTELLEN (.HEB BASEMAP)'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('saving a new preset persists it', (tester) async {
      final storage = t2.MemoryStorage();
      final dongle = t2.FakeDongleService();
      final (container, widget) =
          _buildSession(dongle: dongle, storage: storage);
      addTearDown(container.dispose);

      await tester.pumpWidget(widget);
      await _settleConnect(tester, dongle);

      await tester.tap(find.text('+ NEUES PRESET SPEICHERN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('PRESET SPEICHERN'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'My Trail');
      await tester.tap(find.text('SPEICHERN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('My Trail'), findsOneWidget);
      expect(storage.profiles, hasLength(1));
      expect(storage.profiles.first.name, 'My Trail');
    });

    testWidgets('restore confirmation dialog can be confirmed/cancelled',
        (tester) async {
      final storage = t2.MemoryStorage();
      final dongle = t2.FakeDongleService();
      final (container, widget) = _buildSession(
        dongle: dongle,
        storage: storage,
        extra: [writeSafetyDecisionProvider.overrideWithValue(_allowedSafety)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(widget);
      await _settleConnect(tester, dongle);

      await tester.ensureVisible(
          find.text('WERKSEINSTELLUNGEN WIEDERHERSTELLEN (.HEB BASEMAP)'));
      await tester.pump();
      await tester
          .tap(find.text('WERKSEINSTELLUNGEN WIEDERHERSTELLEN (.HEB BASEMAP)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('WERKSEINSTELLUNGEN WIEDERHERSTELLEN?'), findsOneWidget);

      await tester.tap(find.text('ABBRECHEN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('WERKSEINSTELLUNGEN WIEDERHERSTELLEN?'), findsNothing);
      expect(container.read(tuningProvider).appliedSuccessfully, isFalse);
    });

    testWidgets('apply writes to controller when safety authorized',
        (tester) async {
      final storage = t2.MemoryStorage();
      final dongle = t2.FakeDongleService();
      final (container, widget) = _buildSession(
        dongle: dongle,
        storage: storage,
        extra: [writeSafetyDecisionProvider.overrideWithValue(_allowedSafety)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(widget);
      await _settleConnect(tester, dongle);

      await tester.ensureVisible(find.text('AUF CONTROLLER SCHREIBEN'));
      await tester.pump();
      await tester.tap(find.text('AUF CONTROLLER SCHREIBEN'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VERIFIZIERT SCHREIBEN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(tuningProvider).appliedSuccessfully, isTrue);
      expect(find.text('PARAMETER ERFOLGREICH GESCHRIEBEN & VERIFIZIERT'),
          findsOneWidget);
    });
  });
}
