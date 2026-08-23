import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';

/// One geocoding search result.
class GeoSearchResult {
  final String name;
  final String detail;
  final GeoLatLng location;

  const GeoSearchResult({
    required this.name,
    required this.detail,
    required this.location,
  });
}

/// Free Photon geocoding (Komoot, no API key) with Nominatim fallback.
class GeocodingService {
  GeocodingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _photonUrl = 'https://photon.komoot.io/api/';
  static const _nominatimUrl = 'https://nominatim.openstreetmap.org/search';
  static const _userAgent = 'ArcDash/2.7 (E-Moto Dashboards)';

  Future<List<GeoSearchResult>> search(String query,
      {int limit = 5, String language = 'de'}) async {
    if (query.trim().length < 3) return [];
    try {
      return await _searchPhoton(query, limit, language);
    } catch (_) {
      return _searchNominatim(query, limit);
    }
  }

  Future<List<GeoSearchResult>> _searchPhoton(
      String query, int limit, String lang) async {
    final url = '$_photonUrl?q=${Uri.encodeQueryComponent(query)}'
        '&limit=$limit&lang=$lang';
    final response =
        await _client.get(Uri.parse(url), headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) {
      throw Exception('Photon HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final features = (data['features'] as List).cast<Map<String, dynamic>>();

    return features.map((f) {
      final props = (f['properties'] ?? {}) as Map<String, dynamic>;
      final coords = (f['geometry']['coordinates'] as List);
      final parts = [
        props['name'],
        props['postcode'],
        props['city'],
        props['state'],
      ].whereType<String>().toSet().toList();
      return GeoSearchResult(
        name: props['name'] as String? ?? query,
        detail: parts.skip(1).join(', '),
        location: GeoLatLng(
          latitude: (coords[1] as num).toDouble(),
          longitude: (coords[0] as num).toDouble(),
        ),
      );
    }).toList(growable: false);
  }

  Future<List<GeoSearchResult>> _searchNominatim(
      String query, int limit) async {
    final url = '$_nominatimUrl?q=${Uri.encodeQueryComponent(query)}'
        '&format=json&limit=$limit';
    final response =
        await _client.get(Uri.parse(url), headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) return [];
    final data = jsonDecode(response.body) as List;
    return data.cast<Map<String, dynamic>>().map((e) {
      final display = (e['display_name'] as String?) ?? query;
      final commaIdx = display.indexOf(',');
      return GeoSearchResult(
        name: commaIdx > 0 ? display.substring(0, commaIdx) : display,
        detail: commaIdx > 0 ? display.substring(commaIdx + 2) : '',
        location: GeoLatLng(
          latitude: double.parse(e['lat'] as String),
          longitude: double.parse(e['lon'] as String),
        ),
      );
    }).toList(growable: false);
  }

  void dispose() => _client.close();
}

final geocodingServiceProvider =
    Provider<GeocodingService>((ref) => GeocodingService());
