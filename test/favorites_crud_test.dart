import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';
import 'package:arcdash/models/map_favorite.dart';
import 'package:arcdash/providers/map_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Favorites CRUD & Long-Press Management in MapStateNotifier', () {
    test('addFavorite, updateFavorite, removeFavorite full flow', () {
      final c = MapStateNotifier(null, autoInitGps: false);
      expect(c.state.favorites, isEmpty);

      final fav1 = MapFavorite(
        id: 'home_1',
        title: 'Zuhause',
        location: const GeoLatLng(latitude: 52.5200, longitude: 13.4050),
        type: FavoriteType.home,
        createdAt: DateTime.now(),
      );

      c.addFavorite(fav1);
      expect(c.state.favorites.length, 1);
      expect(c.state.favorites.first.title, 'Zuhause');
      expect(c.state.favorites.first.type, FavoriteType.home);

      // Update existing favorite (e.g. rename or update location)
      final fav1Updated = MapFavorite(
        id: 'home_1',
        title: 'Zuhause Neu',
        location: const GeoLatLng(latitude: 52.5300, longitude: 13.4100),
        type: FavoriteType.home,
        createdAt: DateTime.now(),
      );

      c.updateFavorite(fav1Updated);
      expect(c.state.favorites.length, 1);
      expect(c.state.favorites.first.title, 'Zuhause Neu');
      expect(c.state.favorites.first.location.latitude, 52.5300);

      // Remove favorite
      c.removeFavorite('home_1');
      expect(c.state.favorites, isEmpty);
    });
  });
}
