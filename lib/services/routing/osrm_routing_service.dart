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
    List<GeoLatLng> waypoints = const [],
    RoutingPreference preference = RoutingPreference.fastest,
  }) async {
    final allPoints = [origin, ...waypoints, destination];
    final coordsString =
        allPoints.map((p) => '${p.longitude},${p.latitude}').join(';');

    final url = '$_baseUrl/'
        '$coordsString'
        '?overview=full&geometries=geojson&alternatives=false&steps=true';

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

    final maneuvers = <RouteManeuver>[];
    final legs = (route['legs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final leg in legs) {
      final steps = (leg['steps'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final step in steps) {
        final maneuver = (step['maneuver'] ?? {}) as Map<String, dynamic>;
        final type = maneuver['type'] as String?;
        final modifier = maneuver['modifier'] as String?;
        final name = (step['name'] as String?) ?? '';
        final stepDistance = (step['distance'] as num?)?.toDouble() ?? 0.0;

        var instruction = '';
        if (type == 'depart') {
          instruction = name.isNotEmpty ? 'Start auf $name' : 'Fahrt starten';
        } else if (type == 'arrive') {
          instruction = 'Ziel erreicht';
        } else if (type == 'turn') {
          final modText = switch (modifier) {
            'left' => 'links abbiegen',
            'right' => 'rechts abbiegen',
            'slight left' => 'halb links abbiegen',
            'slight right' => 'halb rechts abbiegen',
            'sharp left' => 'scharf links abbiegen',
            'sharp right' => 'scharf rechts abbiegen',
            'straight' => 'geradeaus weiter',
            _ => 'abbiegen',
          };
          instruction = name.isNotEmpty ? '$modText auf $name' : modText;
        } else if (type == 'continue' || type == 'new name') {
          instruction =
              name.isNotEmpty ? 'Weiter auf $name' : 'Geradeaus weiter';
        } else {
          instruction = name.isNotEmpty ? 'Weiter auf $name' : 'Weiterfahren';
        }

        GeoLatLng? stepLoc;
        final locCoords = (maneuver['location'] as List?)?.cast<dynamic>();
        if (locCoords != null && locCoords.length >= 2) {
          stepLoc = GeoLatLng(
            latitude: (locCoords[1] as num).toDouble(),
            longitude: (locCoords[0] as num).toDouble(),
          );
        }

        maneuvers.add(RouteManeuver(
          instruction: instruction,
          distanceMeters: stepDistance,
          location: stepLoc,
          modifier: modifier,
          type: type,
        ));
      }
    }

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
      maneuvers: maneuvers,
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
