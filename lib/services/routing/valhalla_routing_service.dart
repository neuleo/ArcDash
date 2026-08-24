import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';

/// Free Valhalla routing (FOSSGIS, no API key) — elevation-aware bicycle
/// costing with Mountain profile, returns German maneuver instructions.
class ValhallaRoutingService implements RoutingService {
  ValhallaRoutingService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl = 'https://valhalla1.openstreetmap.de/route';

  @override
  Future<NavigationRoute> calculateRoute({
    required GeoLatLng origin,
    required GeoLatLng destination,
    RoutingPreference preference = RoutingPreference.avoidHighways,
  }) async {
    final body = jsonEncode({
      'locations': [
        {'lat': origin.latitude, 'lon': origin.longitude, 'type': 'break'},
        {
          'lat': destination.latitude,
          'lon': destination.longitude,
          'type': 'break'
        },
      ],
      'costing': 'bicycle',
      'costing_options': {
        'bicycle': {'bicycle_type': 'Mountain', 'use_roads': 0.33},
      },
      'alternatives': false,
      'directions_options': {'language': 'de', 'units': 'kilometers'},
    });

    final response = await _client
        .post(
          Uri.parse(_baseUrl),
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode != 200) {
      throw ValhallaException('HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final trip = data['trip'] as Map<String, dynamic>?;
    if (trip == null) {
      throw ValhallaException('No trip in response');
    }

    // Collect full geometry from encoded polyline + maneuvers.
    final geometry = <GeoLatLng>[];
    double totalKm = 0;
    double totalTime = 0;
    final maneuvers = <RouteManeuver>[];

    for (final leg in (trip['legs'] as List).cast<Map<String, dynamic>>()) {
      totalKm += (leg['length'] as num).toDouble();
      totalTime += (leg['time'] as num).toDouble();
      geometry.addAll(decodePolyline(leg['shape'] as String));
      for (final m in (leg['maneuvers'] as List).cast<Map<String, dynamic>>()) {
        maneuvers.add(RouteManeuver(
          instruction: (m['instruction'] ?? '') as String,
          distanceMeters: ((m['length'] as num?)?.toDouble() ?? 0) * 1000,
        ));
      }
    }

    final distanceM = totalKm * 1000;

    return NavigationRoute(
      segments: [
        RouteSegment(
            start: origin, end: destination, distanceMeters: distanceM),
      ],
      totalDistanceMeters: distanceM,
      preference: preference,
      geometry: geometry,
      durationSeconds: totalTime,
      providerName: 'Valhalla',
      maneuvers: maneuvers,
    );
  }

  /// Decodes Valhalla's encoded polyline (precision **5**, unlike Google's 6).
  static List<GeoLatLng> decodePolyline(String encoded) {
    const invFactor = 1e-5;
    final points = <GeoLatLng>[];
    var index = 0, lat = 0, lng = 0;

    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add(
          GeoLatLng(latitude: lat * invFactor, longitude: lng * invFactor));
    }
    return points;
  }

  void dispose() => _client.close();
}

class ValhallaException implements Exception {
  final String message;
  ValhallaException(this.message);
  @override
  String toString() => 'ValhallaException: $message';
}
