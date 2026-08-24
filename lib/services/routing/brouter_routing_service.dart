import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';

/// Free BRouter routing (brouter.de, no API key) — the only free service with
/// real offroad profiles (mtb = forest/trail preference) and elevation data.
class BRouterRoutingService implements RoutingService {
  BRouterRoutingService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl = 'https://brouter.de/brouter';

  @override
  Future<NavigationRoute> calculateRoute({
    required GeoLatLng origin,
    required GeoLatLng destination,
    List<GeoLatLng> waypoints = const [],
    RoutingPreference preference = RoutingPreference.trailPreferred,
  }) async {
    final brouterProfile = switch (preference) {
      RoutingPreference.fastest => 'moped',
      RoutingPreference.trailPreferred => 'mtb',
      RoutingPreference.avoidHighways ||
      RoutingPreference.shortest =>
        'trekking',
    };

    final allPoints = [origin, ...waypoints, destination];
    final lonlatsString =
        allPoints.map((p) => '${p.longitude},${p.latitude}').join('|');

    final url = '$_baseUrl'
        '?lonlats=$lonlatsString'
        '&profile=$brouterProfile&alternativeidx=0&format=geojson';

    final response = await _client.get(Uri.parse(url)).timeout(
          const Duration(seconds: 25),
        );

    if (response.statusCode != 200) {
      throw BRouterException('HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final features = (data['features'] as List?)?.cast<Map<String, dynamic>>();
    if (features == null || features.isEmpty) {
      throw BRouterException('Empty response');
    }
    final feature = features.first;
    final props = (feature['properties'] ?? {}) as Map<String, dynamic>;

    // Geometry: LineString [[lon, lat, elev], ...] — third value is elevation!
    final coords =
        (feature['geometry']['coordinates'] as List).cast<List<dynamic>>();
    var gain = 0.0;
    double? prevElev;
    for (final c in coords) {
      if (c.length > 2) {
        final e = (c[2] as num?)?.toDouble();
        if (e != null && prevElev != null && e > prevElev) {
          gain += e - prevElev;
        }
        prevElev = e;
      }
    }

    final geometry = coords
        .map((c) => GeoLatLng(
            latitude: (c[1] as num).toDouble(),
            longitude: (c[0] as num).toDouble()))
        .toList(growable: false);

    final trackLengthM =
        double.tryParse('${props['track-length'] ?? 0}') ?? 0.0;
    // BRouter 'total-time' is SECONDS despite sounding like minutes.
    final totalTimeSec = double.tryParse('${props['total-time'] ?? 0}') ?? 0.0;
    final durationS = totalTimeSec > 0
        ? totalTimeSec
        : trackLengthM / 4.5; // ~16 km/h average offroad fallback

    return NavigationRoute(
      segments: [
        RouteSegment(
          start: origin,
          end: destination,
          distanceMeters: trackLengthM,
          surfaceType: brouterProfile == 'mtb' ? 'unpaved' : 'mixed',
        ),
      ],
      totalDistanceMeters: trackLengthM,
      preference: preference,
      geometry: geometry,
      durationSeconds: durationS,
      elevationGainMetersTotal: gain,
      providerName: 'BRouter',
    );
  }

  void dispose() => _client.close();
}

class BRouterException implements Exception {
  final String message;
  BRouterException(this.message);
  @override
  String toString() => 'BRouterException: $message';
}
