import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:arcdash/services/geocoding/geocoding_service.dart';

void main() {
  group('GeocodingService (Photon)', () {
    test('parses real Photon response shape', () async {
      const photonBody = '''
      {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "properties": {"name": "Chorin", "postcode": "16230", "city": "Chorin", "state": "Brandenburg"},
            "geometry": {"type": "Point", "coordinates": [13.87, 52.90]}
          },
          {
            "type": "Feature",
            "properties": {"name": "Naturpark Chorin", "state": "Brandenburg"},
            "geometry": {"type": "Point", "coordinates": [13.86, 52.89]}
          }
        ]
      }''';

      final svc = GeocodingService(
        client: MockClient((req) async {
          expect(req.url.host, 'photon.komoot.io');
          expect(req.url.queryParameters['q'], 'chorin');
          return http.Response(photonBody, 200);
        }),
      );

      final results = await svc.search('chorin');
      expect(results.length, 2);
      expect(results.first.name, 'Chorin');
      expect(results.first.location.latitude, closeTo(52.90, 0.001));
      expect(results.first.location.longitude, closeTo(13.87, 0.001));
      expect(results.first.detail, contains('Brandenburg'));
    });

    test('falls back to Nominatim when Photon fails', () async {
      const nomBody =
          '[{"display_name": "Chorin, Barnim, Brandenburg, Deutschland", '
          '"lat": "52.9036", "lon": "13.8724"}]';

      final svc = GeocodingService(
        client: MockClient((req) async {
          if (req.url.host == 'photon.komoot.io') {
            return http.Response('boom', 500);
          }
          expect(req.url.host, 'nominatim.openstreetmap.org');
          return http.Response(nomBody, 200);
        }),
      );

      final results = await svc.search('chorin');
      expect(results.length, 1);
      expect(results.first.name, 'Chorin');
      expect(results.first.location.latitude, closeTo(52.9036, 0.0001));
    });

    test('short queries are skipped entirely', () async {
      var called = false;
      final svc = GeocodingService(
        client: MockClient((_) async {
          called = true;
          return http.Response('[]', 200);
        }),
      );
      final results = await svc.search('ab');
      expect(results, isEmpty);
      expect(called, isFalse);
    });
  });
}
