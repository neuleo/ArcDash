import 'package:arcdash/app.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/screens/dashboard_screen.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:arcdash/utils/crc_calculator.dart';
import 'package:arcdash/utils/packet_parser.dart';
import 'package:arcdash/utils/unit_converter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('ArcDash starts on the dashboard route', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
          storageServiceProvider.overrideWithValue(StorageService()),
        ],
        child: const ArcDashApp(),
      ),
    );

    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  testWidgets('dashboard exposes an explicit layout editor', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
          storageServiceProvider.overrideWithValue(StorageService()),
        ],
        child: const ArcDashApp(),
      ),
    );

    await tester.tap(find.byTooltip('Dashboard bearbeiten'));
    await tester.pump();

    expect(find.byTooltip('Wert hinzufügen'), findsOneWidget);
    expect(find.text('Hoch'), findsOneWidget);
    expect(find.text('Quer'), findsOneWidget);
  });

  testWidgets('dashboard renders a cockpit dial instead of text cards',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
          storageServiceProvider.overrideWithValue(StorageService()),
        ],
        child: const ArcDashApp(),
      ),
    );

    expect(find.text('RIDE COMPUTER'), findsOneWidget);
    expect(find.byKey(const Key('speed-dial')), findsOneWidget);
    expect(find.text('Cockpit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cockpit layout renders in landscape without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
          storageServiceProvider.overrideWithValue(StorageService()),
        ],
        child: const ArcDashApp(),
      ),
    );

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses offline localization and glove-friendly controls',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
          storageServiceProvider.overrideWithValue(StorageService()),
        ],
        child: const ArcDashApp(),
      ),
    );

    final appFinder = find.byType(MaterialApp);
    final materialApp = tester.widget<MaterialApp>(appFinder);

    expect(materialApp.supportedLocales, const [Locale('de'), Locale('en')]);
    expect(materialApp.locale, const Locale('de'));
  });

  test('CRC validates generated packets and rejects mutations', () {
    final packet = List<int>.filled(16, 0);
    packet[0] = 0xAA;
    packet[1] = 0x03;
    packet[2] = 0x42;

    CrcCalculator.computeCRC(packet, packet.length);

    expect(CrcCalculator.verifyCRC(packet, packet.length), isTrue);
    packet[2] ^= 0x01;
    expect(CrcCalculator.verifyCRC(packet, packet.length), isFalse);
  });

  test('packet parser extracts a valid status packet and rejects short data',
      () {
    final packet = List<int>.filled(16, 0);
    packet[0] = 0xAA;
    packet[1] = 0x03;
    packet[2] = 0x10;
    CrcCalculator.computeCRC(packet, packet.length);

    final parsed = PacketParser.parseStatusPacket(packet);

    expect(parsed, isNotNull);
    expect(parsed!.address, 0x00);
    expect(parsed.rawData, hasLength(12));
    expect(PacketParser.parseStatusPacket(packet.sublist(0, 8)), isNull);
    expect(PacketParser.extractPackets([0x01, ...packet]), [packet]);
  });

  test('core unit conversions handle limits and zero denominators', () {
    expect(UnitConverter.kphToMph(100), closeTo(62.1371, 0.0001));
    expect(UnitConverter.speedUnit(true), 'mph');
    expect(
        UnitConverter.batteryPercent(
          voltageDeciVolts: 500,
          zeroBattCoeff: 600,
          fullBattCoeff: 700,
        ),
        0);
    expect(
        UnitConverter.batteryPercent(
          voltageDeciVolts: 750,
          zeroBattCoeff: 600,
          fullBattCoeff: 700,
        ),
        100);
    expect(
        UnitConverter.estimatedRangeKm(
          batteryPercent: 50,
          battCapacityWh: 4000,
          avgConsumptionWhPerKm: 100,
        ),
        20);
    expect(
        UnitConverter.estimatedRangeKm(
          batteryPercent: 50,
          battCapacityWh: 4000,
          avgConsumptionWhPerKm: 0,
        ),
        0);
  });
}

class _FakeDongleService extends DongleService {
  @override
  Stream<DongleConnectionState> get connectionStateStream =>
      Stream.value(DongleConnectionState.idle);

  @override
  Stream<List<int>> get rawDataStream => const Stream.empty();

  @override
  Stream<List<DiscoveredDongle>> get scanResultsStream => const Stream.empty();

  @override
  DongleConnectionState get state => DongleConnectionState.idle;

  @override
  Future<bool> isBluetoothOn() async => false;

  @override
  Future<void> startScan(
      {Duration timeout = const Duration(seconds: 10)}) async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<bool> write(List<int> data) async => false;

  @override
  void dispose() {}
}
