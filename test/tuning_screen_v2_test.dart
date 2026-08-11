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

/// Builds a valid 16-byte FarDriver status frame. [id] selects the rotating
/// block (0 -> 0xE2, 6 -> 0x12 maxSpeed, 10 -> 0x18 maxLineCurrent).
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

Future<void> _settleConnect(WidgetTester tester, t2.FakeDongleService dongle) async {
  await tester.pump(const Duration(milliseconds: 600));
  // A telemetry frame fills the sample buffer so the stream-init retry timer
  // cancels itself and no timer leaks into a later assertion.
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
  group('T090/T091 - preset UI', () {
    testWidgets('lists factory presets plus saved custom presets',
        (tester) async {
      final storage = t2.MemoryStorage();
      await storage.saveProfile(TuningProfile.custom().copyWith(name: 'My Trail'));
      final dongle = t2.FakeDongleService();
      final (container, widget) = _buildSession(dongle: dongle, storage: storage);
      addTearDown(container.dispose);

      await tester.pumpWidget(widget);
      await _settleConnect(tester, dongle);

      expect(find.text('STOCK OFFROAD'), findsOneWidget);
      expect(find.text('ECO RANGE'), findsOneWidget);
      expect(find.text('CUSTOM'), findsOneWidget);
      expect(find.text('MY TRAIL'), findsOneWidget);
      expect(find.text('+ NEUES PRESET SPEICHERN'), findsOneWidget);
      expect(find.text('WERKSEINSTELLUNGEN WIEDERHERSTELLEN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('saving a new preset persists it and shows the custom chip',
        (tester) async {
      final storage = t2.MemoryStorage();
      final dongle = t2.FakeDongleService();
      final (container, widget) = _buildSession(dongle: dongle, storage: storage);
      addTearDown(container.dispose);

      await tester.pumpWidget(widget);
      await _settleConnect(tester, dongle);

      await tester.tap(find.text('+ NEUES PRESET SPEICHERN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('NEUES PRESET SPEICHERN'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'My Trail');
      await tester.tap(find.text('SPEICHERN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('MY TRAIL'), findsOneWidget);
      expect(find.text('Preset "My Trail" gespeichert'), findsOneWidget);
      expect(storage.profiles, hasLength(1));
      expect(storage.profiles.first.name, 'My Trail');

      // Flush the snackbar auto-dismiss timer.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('deleting a custom preset removes the chip after confirmation',
        (tester) async {
      final storage = t2.MemoryStorage();
      await storage.saveProfile(TuningProfile.custom().copyWith(name: 'My Trail'));
      final dongle = t2.FakeDongleService();
      final (container, widget) = _buildSession(dongle: dongle, storage: storage);
      addTearDown(container.dispose);

      await tester.pumpWidget(widget);
      await _settleConnect(tester, dongle);
      expect(find.text('MY TRAIL'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('PRESET LÖSCHEN?'), findsOneWidget);

      await tester.tap(find.text('LÖSCHEN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('MY TRAIL'), findsNothing);
      expect(storage.profiles, isEmpty);

      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('T092 - restore UX', () {
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

      await tester.ensureVisible(find.text('WERKSEINSTELLUNGEN WIEDERHERSTELLEN'));
      await tester.pump();
      await tester.tap(find.text('WERKSEINSTELLUNGEN WIEDERHERSTELLEN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('WERKSRESTORE?'), findsOneWidget);

      await tester.tap(find.text('CANCEL'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('WERKSRESTORE?'), findsNothing);
      expect(container.read(tuningProvider).appliedSuccessfully, isFalse);

      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('T093 - read-back verification', () {
    testWidgets('confirmed values show the Verifiziert banner after read-back',
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

      // Apply the default Custom preset (65 km/h, 100 A).
      await tester.ensureVisible(find.text('APPLY TO CONTROLLER'));
      await tester.pump();
      await tester.tap(find.text('APPLY TO CONTROLLER'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('APPLY CHANGES?'), findsOneWidget);

      await tester.tap(find.text('APPLY'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(tuningProvider).appliedSuccessfully, isTrue);
      // Read-back not observed yet -> pending banner.
      expect(find.text('READ-BACK AUSSTEHEND'), findsOneWidget);

      // Emit status frames carrying the written raw values (0x12 block -> 0x15
      // maxSpeed raw 4680 = 65 km/h, 0x18 block -> 0x19 line current raw 400).
      final speedData = List<int>.filled(12, 0);
      const expectedSpeedRaw = 65 * 72;
      speedData[6] = expectedSpeedRaw & 0xFF;
      speedData[7] = (expectedSpeedRaw >> 8) & 0xFF;
      dongle.emit(_statusPacket(6, speedData));

      final lineData = List<int>.filled(12, 0);
      const expectedLineRaw = 100 * 4;
      lineData[2] = expectedLineRaw & 0xFF;
      lineData[3] = (expectedLineRaw >> 8) & 0xFF;
      dongle.emit(_statusPacket(10, lineData));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('VERIFIZIERT'), findsOneWidget);
      expect(find.text('READ-BACK AUSSTEHEND'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}