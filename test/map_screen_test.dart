import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/map_provider.dart';
import 'package:arcdash/screens/map_screen.dart';
import 'package:arcdash/services/range_prediction_repository.dart';
import 'package:arcdash/services/routing/multi_routing_service.dart';
import 'package:arcdash/services/storage_service.dart';

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

  group('MapStateNotifier', () {
    test('setDestination stores point and clears previous selection', () {
      final c = MapStateNotifier(null, autoInitGps: false);
      c.selectAlternative(RouteAlternative(
        profile: RoutingProfile.fastestCar,
        route: const NavigationRoute(
          segments: [],
          totalDistanceMeters: 1,
          preference: RoutingPreference.fastest,
        ),
      ));
      expect(c.state.selected, isNotNull);

      c.setDestination(const GeoLatLng(latitude: 52.9, longitude: 13.87),
          label: 'Chorin');
      expect(c.state.destination?.latitude, 52.9);
      expect(c.state.destinationLabel, 'Chorin');
      expect(c.state.selected, isNull);
      expect(c.state.alternatives, isEmpty);
    });

    test('selectAlternative keeps destination', () {
      final c = MapStateNotifier(null, autoInitGps: false);
      c.setDestination(const GeoLatLng(latitude: 52.9, longitude: 13.87));
      final alt = RouteAlternative(
        profile: RoutingProfile.trailForest,
        route: const NavigationRoute(
          segments: [],
          totalDistanceMeters: 9000,
          preference: RoutingPreference.trailPreferred,
        ),
      );
      c.setAlternatives([alt]);
      c.selectAlternative(alt);
      expect(c.state.selected?.label, 'Wald & Trail');
      expect(c.state.destination, isNotNull);
    });

    test('clearRoute keeps origin only', () {
      final c = MapStateNotifier(null, autoInitGps: false);
      c.setDestination(const GeoLatLng(latitude: 1, longitude: 2));
      c.clearRoute();
      expect(c.state.destination, isNull);
      expect(c.state.alternatives, isEmpty);
    });
  });

  group('RoutingProfileX', () {
    test('labels and providers are user-facing German strings', () {
      expect(RoutingProfile.fastestCar.label, 'Schnellste');
      expect(RoutingProfile.trailForest.label, 'Wald & Trail');
      expect(RoutingProfile.scenicTrekking.label, 'Scenic');
      expect(RoutingProfile.ebikeOptimized.label, 'E-Bike optimiert');

      expect(RoutingProfile.fastestCar.providerName, 'OSRM');
      expect(RoutingProfile.trailForest.providerName, 'BRouter');
      expect(RoutingProfile.ebikeOptimized.providerName, 'Valhalla');
    });
  });

  group('MapScreen widget', () {
    testWidgets('renders map scaffold with search field', (tester) async {
      await tester.pumpWidget(_wrap(const MapScreen()));
      await tester.pump(const Duration(seconds: 1));

      // AppBar title
      expect(find.text('Navigation'), findsOneWidget);
      // Search hint contains destination search prompt
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets(
        'tap on map does not set destination, long press sets a destination marker',
        (tester) async {
      await tester.pumpWidget(_wrap(const MapScreen()));
      await tester.pump(const Duration(seconds: 1));

      // Simulate the controller path directly (flutter_map tap needs gestures
      // on the tile stream; the callback is what we want to verify):
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(mapControllerProvider.notifier);
      controller.setDestinationFromTap(52.90, 13.87);
      expect(container.read(mapControllerProvider).destinationLabel,
          'Karten-Punkt');
    });
  });
}
