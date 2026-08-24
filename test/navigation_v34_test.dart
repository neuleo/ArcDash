import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/map_provider.dart';
import 'package:arcdash/screens/map_screen.dart';
import 'package:arcdash/services/navigation/map_favorites_repository.dart';
import 'package:arcdash/services/range_prediction_repository.dart';
import 'package:arcdash/services/routing/multi_routing_service.dart';
import 'package:arcdash/services/storage_service.dart';

Widget _wrap(Widget child, {Size size = const Size(1200, 800)}) {
  final memoryStorage = MemoryStorage();
  final repo = RangePredictionRepository(storage: memoryStorage);
  final favRepo = MapFavoritesRepository(storage: memoryStorage);

  return ProviderScope(
    overrides: [
      storageServiceProvider.overrideWithValue(StorageService()),
      rangePredictionRepositoryProvider.overrideWithValue(repo),
      mapFavoritesRepositoryProvider.overrideWithValue(favRepo),
      rangePredictionStateProvider.overrideWith(
          (ref) => RangePredictionNotifier(repo, 'TEST_CONTROLLER')),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Waypoints & Roundtrip Navigation in MapStateNotifier', () {
    test('addWaypoint, removeWaypoint and toggleRoundTrip update state', () {
      final c = MapStateNotifier(null, autoInitGps: false);
      expect(c.state.waypoints, isEmpty);
      expect(c.state.isRoundTrip, isFalse);

      const p1 = GeoLatLng(latitude: 52.51, longitude: 13.38);
      const p2 = GeoLatLng(latitude: 52.53, longitude: 13.40);

      c.addWaypoint(p1);
      c.addWaypoint(p2);
      expect(c.state.waypoints.length, 2);

      c.removeWaypoint(0);
      expect(c.state.waypoints.length, 1);
      expect(c.state.waypoints.first.latitude, 52.53);

      c.toggleRoundTrip();
      expect(c.state.isRoundTrip, isTrue);
    });
  });

  group('Landscape Layout rendering', () {
    testWidgets(
        'MapScreen renders in Landscape without full AppBar and with compact floating card',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester
          .pumpWidget(_wrap(const MapScreen(), size: const Size(1280, 800)));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.add_location_alt_outlined), findsOneWidget);
    });
  });
}
