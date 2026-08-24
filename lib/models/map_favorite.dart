import 'dart:convert';
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';

enum FavoriteType { home, work, custom, recent }

class MapFavorite {
  final String id;
  final String title;
  final String subtitle;
  final GeoLatLng location;
  final FavoriteType type;
  final DateTime createdAt;

  const MapFavorite({
    required this.id,
    required this.title,
    this.subtitle = '',
    required this.location,
    required this.type,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'lat': location.latitude,
        'lon': location.longitude,
        'type': type.name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory MapFavorite.fromJson(Map<String, dynamic> json) => MapFavorite(
        id: json['id'] as String,
        title: json['title'] as String,
        subtitle: (json['subtitle'] as String?) ?? '',
        location: GeoLatLng(
          latitude: (json['lat'] as num).toDouble(),
          longitude: (json['lon'] as num).toDouble(),
        ),
        type: FavoriteType.values
            .byName((json['type'] as String?) ?? FavoriteType.custom.name),
        createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
            DateTime.now(),
      );
}
