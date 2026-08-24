import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';

/// One EV charging point or power socket found via OpenStreetMap.
class ChargingStationPoi {
  final String id;
  final String name;
  final String operatorName;
  final GeoLatLng location;
  final bool hasSchuko; // 230V Standard socket (ideal for E-Moto charger)
  final String socketInfo;

  const ChargingStationPoi({
    required this.id,
    required this.name,
    required this.operatorName,
    required this.location,
    this.hasSchuko = false,
    this.socketInfo = '',
  });
}

/// Free Overpass API service querying OSM for EV charging and power sockets.
class ChargingStationService {
  ChargingStationService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;
  static const _overpassUrl = 'https://overpass-api.de/api/interpreter';
  static const _kDefaultUserAgent = 'ArcDash/3.4 (E-Moto Companion App)';

  Future<List<ChargingStationPoi>> findNearbyCharging({
    required GeoLatLng center,
    double radiusMeters = 25000,
  }) async {
    final query = '''
[out:json][timeout:15];
(
  node["amenity"="charging_station"](around:$radiusMeters,${center.latitude},${center.longitude});
  way["amenity"="charging_station"](around:$radiusMeters,${center.latitude},${center.longitude});
  node["socket:schuko"="yes"](around:$radiusMeters,${center.latitude},${center.longitude});
);
out center 40;
''';

    try {
      final response = await _client.post(
        Uri.parse(_overpassUrl),
        headers: {'User-Agent': _kDefaultUserAgent},
        body: {'data': query},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final elements =
          (data['elements'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      return elements
          .map((e) {
            final tags = (e['tags'] ?? {}) as Map<String, dynamic>;
            final lat = (e['lat'] as num?)?.toDouble() ??
                (e['center']?['lat'] as num?)?.toDouble() ??
                0.0;
            final lon = (e['lon'] as num?)?.toDouble() ??
                (e['center']?['lon'] as num?)?.toDouble() ??
                0.0;
            if (lat == 0.0 && lon == 0.0) return null;
            final name = (tags['name'] as String?) ??
                (tags['operator'] as String?) ??
                'Ladesäule / Steckdose';
            final hasSchuko = tags['socket:schuko'] == 'yes' ||
                tags['socket:type2_combo'] != null;

            final sockets = <String>[];
            if (tags['socket:schuko'] == 'yes') sockets.add('Schuko (230V)');
            if (tags['socket:type2'] == 'yes') sockets.add('Typ 2');
            if (tags['socket:type2_combo'] == 'yes') sockets.add('CCS');

            return ChargingStationPoi(
              id: '${e['id']}',
              name: name,
              operatorName: (tags['operator'] as String?) ?? '',
              location: GeoLatLng(latitude: lat, longitude: lon),
              hasSchuko: hasSchuko,
              socketInfo: sockets.isNotEmpty ? sockets.join(', ') : 'Ladesäule',
            );
          })
          .whereType<ChargingStationPoi>()
          .toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  void dispose() => _client.close();
}
