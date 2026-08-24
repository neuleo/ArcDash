import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/map_provider.dart';
import 'package:arcdash/screens/map_screen.dart';
import 'package:arcdash/services/navigation/navigation_engine.dart';
import 'package:arcdash/services/range_prediction_repository.dart';
import 'package:arcdash/services/routing/multi_routing_service.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:arcdash/widgets/map_cockpit_hud.dart';
import 'package:arcdash/widgets/route_elevation_chart.dart';

Widget _wrap(Widget child) {
  final memoryStorage = MemoryStorage();
  final repo = RangePredictionRepository(storage: memoryStorage);
  return ProviderScope(
    overrides: [
      storageServiceProvider.overrideWithValue(StorageService()),
      rangePredictionRepositoryProvider.overrideWithValue(repo),
      rangePredictionStateProvider.overrideWith(
          (ref) => RangePredictionNotifier(repo, 'TEST_CONTROLLER')),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NavigationEngine', () {
    test('calculates distance and bearing between points accurately', () {
      const a = GeoLatLng(latitude: 52.5200, longitude: 13.4050);
      const b = GeoLatLng(latitude: 52.5200, longitude: 13.4150);

      final d = NavigationEngine.distanceBetween(a, b);
      expect(d, closeTo(677, 10)); // approx 677m at 52 deg lat

      final bearing = NavigationEngine.bearingBetween(a, b);
      expect(bearing, closeTo(90, 5)); // East
    });
  });

  group('MapStateNotifier Navigation Controls', () {
    test('startNavigation and nextManeuver step through guidance', () {
      final c = MapStateNotifier(null, autoInitGps: false);
      const route = NavigationRoute(
        segments: [],
        totalDistanceMeters: 5000,
        preference: RoutingPreference.fastest,
        maneuvers: [
          RouteManeuver(instruction: 'Start', distanceMeters: 100),
          RouteManeuver(instruction: 'Rechts abbiegen', distanceMeters: 400),
        ],
      );
      final alt =
          RouteAlternative(profile: RoutingProfile.fastestCar, route: route);
      c.setAlternatives([alt]);
      c.selectAlternative(alt);

      expect(c.state.isNavigating, isFalse);
      expect(c.state.currentManeuverIndex, 0);

      c.startNavigation();
      expect(c.state.isNavigating, isTrue);

      c.nextManeuver();
      expect(c.state.currentManeuverIndex, 1);

      c.stopNavigation();
      expect(c.state.isNavigating, isFalse);
    });
  });

  group('MapScreen Extra Widgets', () {
    testWidgets('MapCockpitHud renders speed, soc, and kw', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: MapCockpitHud(
            speedKph: 45.0,
            socPercent: 88,
            powerKw: 3.4,
          ),
        ),
      ));

      expect(find.text('45'), findsOneWidget);
      expect(find.text('88 %'), findsOneWidget);
      expect(find.text('3.4 kW'), findsOneWidget);
    });

    testWidgets('RouteElevationChart renders with gain', (tester) async {
      const route = NavigationRoute(
        segments: [],
        totalDistanceMeters: 12000,
        elevationGainMetersTotal: 140,
        preference: RoutingPreference.trailPreferred,
      );

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: RouteElevationChart(route: route),
        ),
      ));

      expect(find.text('HÖHENPROFIL (+140 m)'), findsOneWidget);
    });

    testWidgets('MapScreen renders scaffold and action buttons',
        (tester) async {
      await tester.pumpWidget(_wrap(const MapScreen()));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.ev_station), findsOneWidget);
      expect(find.byIcon(Icons.my_location), findsOneWidget);
    });
  });
}
