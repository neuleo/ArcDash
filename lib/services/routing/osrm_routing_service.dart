import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';

/// Free OSRM routing via the FOSSGIS community server (no API key).
///
/// Endpoint: https://routing.openstreetmap.de/routed-car/route/v1/driving/
/// Fair-use only — see plan/16-map-navigation.md.
class OsrmRoutingService implements RoutingService {
  OsrmRoutingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl =
      'https://routing.openstreetmap.de/routed-car/route/v1/driving';

  @override
  Future<NavigationRoute> calculateRoute({
    required GeoLatLng origin,
    required GeoLatLng destination,
    RoutingPreference preference = RoutingPreference.fastest,
  }) async {
    final url = '$_baseUrl/'
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson&alternatives=false&steps=false';

    final response = await _client.get(Uri.parse(url)).timeout(
          const Duration(seconds: 20),
        );

    if (response.statusCode != 200) {
      throw OsrmException('HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['code'] != 'Ok') {
      throw OsrmException('OSRM code: ${data['code']}');
    }

    final routes = (data['routes'] as List).cast<Map<String, dynamic>>();
    if (routes.isEmpty) {
      throw OsrmException('No routes');
    }
    final route = routes.first;

    // Geometry: GeoJSON LineString coordinates [[lon, lat], ...]
    final coords = (route['geometry']['coordinates'] as List)
        .cast<List<dynamic>>()
        .map((c) => GeoLatLng(
            latitude: (c[1] as num).toDouble(),
            longitude: (c[0] as num).toDouble()))
        .toList(growable: false);

    final distanceM = (route['distance'] as num).toDouble();
    final durationS = (route['duration'] as num).toDouble();

    return NavigationRoute(
      segments: [
        RouteSegment(
          start: origin,
          end: destination,
          distanceMeters: distanceM,
        ),
      ],
      totalDistanceMeters: distanceM,
      preference: preference,
      geometry: coords,
      durationSeconds: durationS,
      providerName: 'OSRM',
    );
  }

  void dispose() => _client.close();
}

class OsrmException implements Exception {
  final String message;
  OsrmException(this.message);
  @override
  String toString() => 'OsrmException: $message';
}
