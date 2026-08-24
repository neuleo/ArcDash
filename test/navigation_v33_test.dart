import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';
import 'package:arcdash/models/map_favorite.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/map_provider.dart';
import 'package:arcdash/screens/map_screen.dart';
import 'package:arcdash/services/navigation/learned_energy_model.dart';
import 'package:arcdash/services/navigation/map_favorites_repository.dart';
import 'package:arcdash/services/navigation/navigation_engine.dart';
import 'package:arcdash/services/range_prediction_repository.dart';
import 'package:arcdash/services/routing/multi_routing_service.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:arcdash/widgets/map_cockpit_hud.dart';
import 'package:arcdash/widgets/route_elevation_chart.dart';

Widget _wrap(Widget child) {
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
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LearnedEnergyModel', () {
    test('uses fallback defaults when rangeState is null', () {
      final model = LearnedEnergyModel.fromRangeState(null);
      expect(model.learnedCapacityWh, 4000.0);
      expect(model.baseWhPerKm, 35.0);
    });
  });

  group('MapFavoritesRepository', () {
    test('saves and retrieves favorites and recents', () {
      final storage = MemoryStorage();
      final repo = MapFavoritesRepository(storage: storage);

      final fav = MapFavorite(
        id: '1',
        title: 'Zuhause',
        location: const GeoLatLng(latitude: 52.52, longitude: 13.40),
        type: FavoriteType.home,
        createdAt: DateTime.now(),
      );

      repo.setSpecialFavorite(FavoriteType.home, fav);
      final retrieved = repo.getSpecialFavorite(FavoriteType.home);
      expect(retrieved?.title, 'Zuhause');
      expect(retrieved?.location.latitude, 52.52);
    });
  });

  group('MapStateNotifier Trip Planner & Perspective', () {
    test('planningStartSocOverride updates state and clears', () {
      final c = MapStateNotifier(null, autoInitGps: false);
      expect(c.state.planningStartSocOverride, isNull);

      c.setPlanningStartSoc(65.0);
      expect(c.state.planningStartSocOverride, 65.0);

      c.setPlanningStartSoc(null);
      expect(c.state.planningStartSocOverride, isNull);
    });

    test('togglePerspective switches between northUp and headUp', () {
      final c = MapStateNotifier(null, autoInitGps: false);
      expect(c.state.perspective, MapPerspective.northUp);

      c.togglePerspective();
      expect(c.state.perspective, MapPerspective.headUp);

      c.togglePerspective();
      expect(c.state.perspective, MapPerspective.northUp);
    });

    test('userZoom and autoFollowUser state', () {
      final c = MapStateNotifier(null, autoInitGps: false);
      c.setUserZoom(16.5);
      expect(c.state.userZoom, 16.5);

      c.setAutoFollow(false);
      expect(c.state.autoFollowUser, isFalse);
    });
  });

  group('MapScreen Widget Tests', () {
    testWidgets('MapScreen renders all actions and search', (tester) async {
      await tester.pumpWidget(_wrap(const MapScreen()));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.tune), findsOneWidget); // Tour Planner
      expect(find.byIcon(Icons.north), findsOneWidget); // Compass / Perspective
      expect(find.byIcon(Icons.ev_station), findsOneWidget); // EV POIs
      expect(find.byIcon(Icons.my_location), findsOneWidget);
    });
  });
}
