import 'dart:convert';
import 'package:arcdash/models/map_favorite.dart';
import 'package:arcdash/services/range_prediction_repository.dart';

class MapFavoritesRepository {
  static const String _favoritesKey = 'map_favorites_list';
  static const String _recentsKey = 'map_recents_list';

  final KeyValueStorage _storage;

  MapFavoritesRepository({required KeyValueStorage storage})
      : _storage = storage;

  List<MapFavorite> loadFavorites() {
    final raw = _storage.read(_favoritesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => MapFavorite.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void saveFavorites(List<MapFavorite> favorites) {
    final raw = jsonEncode(favorites.map((f) => f.toJson()).toList());
    _storage.write(_favoritesKey, raw);
  }

  List<MapFavorite> loadRecents() {
    final raw = _storage.read(_recentsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => MapFavorite.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void saveRecents(List<MapFavorite> recents) {
    final raw = jsonEncode(recents.map((f) => f.toJson()).toList());
    _storage.write(_recentsKey, raw);
  }

  void addRecent(MapFavorite recent) {
    final list = loadRecents();
    list.removeWhere((e) =>
        e.title == recent.title ||
        (e.location.latitude == recent.location.latitude &&
            e.location.longitude == recent.location.longitude));
    list.insert(0, recent);
    if (list.length > 8) {
      list.removeRange(8, list.length);
    }
    saveRecents(list);
  }

  void setSpecialFavorite(FavoriteType type, MapFavorite favorite) {
    final list = loadFavorites();
    list.removeWhere((e) => e.type == type);
    list.insert(0, favorite);
    saveFavorites(list);
  }

  MapFavorite? getSpecialFavorite(FavoriteType type) {
    final list = loadFavorites();
    try {
      return list.firstWhere((e) => e.type == type);
    } catch (_) {
      return null;
    }
  }
}
