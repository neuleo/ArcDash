import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';
import 'package:arcdash/services/routing/osrm_routing_service.dart';
import 'package:arcdash/services/routing/brouter_routing_service.dart';
import 'package:arcdash/services/routing/valhalla_routing_service.dart';
import 'package:arcdash/services/routing/multi_routing_service.dart';

const origin = GeoLatLng(latitude: 52.5170, longitude: 13.3888);
const dest = GeoLatLng(latitude: 52.5223, longitude: 13.3976);

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

http.Response _ok(String body) =>
    http.Response(body, 200, headers: {'content-type': 'application/json'});

void main() {
  group('OsrmRoutingService (fixture: real FOSSGIS response)', () {
    test('parses distance, duration and geometry', () async {
      final svc = OsrmRoutingService(
        client: MockClient((_) async => _ok(fixture('osrm_route.json'))),
      );
      final route = await svc.calculateRoute(origin: origin, destination: dest);

      expect(route.providerName, 'OSRM');
      expect(route.totalDistanceMeters, greaterThan(1000));
      expect(route.totalDistanceMeters, lessThan(5000));
      expect(route.durationSeconds, greaterThan(60));
      expect(route.geometry.length, greaterThan(20));
      // Berlin coords sanity
      expect(route.geometry.first.latitude, closeTo(52.51, 0.1));
      expect(route.geometry.first.longitude, closeTo(13.38, 0.1));
    });

    test('throws on error code', () async {
      final svc = OsrmRoutingService(
        client: MockClient((_) async => _ok('{"code":"NoRoute","routes":[]}')),
      );
      expect(
        () => svc.calculateRoute(origin: origin, destination: dest),
        throwsA(isA<OsrmException>()),
      );
    });
  });

  group('BRouterRoutingService (fixtures: real mtb/trekking responses)', () {
    test('mtb profile parses track length, elevation gain, geometry', () async {
      final svc = BRouterRoutingService(
        client: MockClient((_) async => _ok(fixture('brouter_mtb.geojson'))),
      );
      final route = await svc.calculateRoute(
          origin: origin,
          destination: dest,
          preference: RoutingPreference.trailPreferred);

      expect(route.providerName, 'BRouter');
      expect(route.totalDistanceMeters, greaterThan(500));
      expect(route.geometry.length, greaterThan(10));
      expect(route.segments.first.surfaceType, 'unpaved');
      // Fixture: total-time 210 s for 1274 m → ~3.5 min, plausible.
      expect(route.durationSeconds, closeTo(210, 1));
      expect(route.durationSeconds, lessThan(3600)); // never hours for 1 km
    });

    test('trekking profile maps to mixed surface', () async {
      final svc = BRouterRoutingService(
        client:
            MockClient((_) async => _ok(fixture('brouter_trekking.geojson'))),
      );
      final route = await svc.calculateRoute(
          origin: origin,
          destination: dest,
          preference: RoutingPreference.avoidHighways);

      expect(route.segments.first.surfaceType, 'mixed');
    });

    test('throws on empty features', () async {
      final svc = BRouterRoutingService(
        client: MockClient((_) async => _ok('{"features": []}')),
      );
      expect(
        () => svc.calculateRoute(origin: origin, destination: dest),
        throwsA(isA<BRouterException>()),
      );
    });
  });

  group('ValhallaRoutingService', () {
    const valhallaResponse = '''
    {
      "trip": {
        "legs": [
          {
            "length": 1.4,
            "time": 280,
            "shape": "gfp_I__vpAoKwLoK_XcGgO",
            "maneuvers": [
              {"instruction": "Fahre suedlich auf der Friedrichstrasse.", "length": 0.3}
            ]
          }
        ]
      }
    }''';

    test('parses trip, geometry from encoded polyline, maneuvers', () async {
      final svc = ValhallaRoutingService(
        client: MockClient((_) async => _ok(valhallaResponse)),
      );
      final route = await svc.calculateRoute(origin: origin, destination: dest);

      expect(route.providerName, 'Valhalla');
      expect(route.totalDistanceMeters, closeTo(1400, 1));
      expect(route.durationSeconds, closeTo(280, 1));
      expect(route.geometry.length, 4);
      // First point of the roundtrip-verified encoding
      expect(route.geometry.first.latitude, closeTo(52.517, 0.0001));
      expect(route.geometry.first.longitude, closeTo(13.3888, 0.0001));
      expect(route.geometry.last.latitude, closeTo(52.5223, 0.0001));
    });

    test('decodePolyline handles multi-char sequences', () {
      // Known encoded value for a longer path
      final pts = ValhallaRoutingService.decodePolyline('_p~iF~ps|U_ulLnnqC');
      expect(pts.length, 2);
      expect(pts.first.latitude, closeTo(38.5, 0.01));
      expect(pts.first.longitude, closeTo(-120.2, 0.01));
      expect(pts.last.latitude, closeTo(40.7, 0.01));
      expect(pts.last.longitude, closeTo(-120.95, 0.01));
    });
  });

  group('MultiRoutingService', () {
    test('valhalla failure falls back to OSRM for ebike profile', () async {
      final svc = MultiRoutingService(
        osrm: OsrmRoutingService(
            client: MockClient((_) async => _ok(fixture('osrm_route.json')))),
        brouter: BRouterRoutingService(
            client:
                MockClient((_) async => _ok(fixture('brouter_mtb.geojson')))),
        valhalla: ValhallaRoutingService(
            client: MockClient((_) async => http.Response('err', 500))),
      );

      final alts =
          await svc.fetchAlternatives(origin: origin, destination: dest);

      // Valhalla fails → OSRM fallback keeps the ebike option alive: 4 total.
      expect(alts.length, 4);
      expect(alts.map((a) => a.provider), containsAll(['OSRM', 'BRouter']));
      expect(
          alts.map((a) => a.profile), contains(RoutingProfile.ebikeOptimized));
    });

    test('total outage of valhalla+brouter still yields OSRM options',
        () async {
      final svc = MultiRoutingService(
        osrm: OsrmRoutingService(
            client: MockClient((_) async => _ok(fixture('osrm_route.json')))),
        brouter: BRouterRoutingService(
            client: MockClient((_) async => http.Response('err', 500))),
        valhalla: ValhallaRoutingService(
            client: MockClient((_) async => http.Response('err', 500))),
      );

      final alts =
          await svc.fetchAlternatives(origin: origin, destination: dest);

      // OSRM survives for fastestCar AND as ebike fallback.
      expect(alts.length, 2);
      expect(alts.every((a) => a.provider == 'OSRM'), isTrue);
    });

    test('RouteAlternative formatting with energy estimation', () {
      final route = NavigationRoute(
        segments: const [
          RouteSegment(start: origin, end: dest, distanceMeters: 4200),
        ],
        totalDistanceMeters: 4200,
        preference: RoutingPreference.fastest,
        durationSeconds: 750,
        elevationGainMetersTotal: 45,
        providerName: 'OSRM',
        geometry: const [origin, dest],
      );
      final alt = RouteAlternative(
        profile: RoutingProfile.fastestCar,
        route: route,
        energyEstimation: const EnergyEstimationResult(
          requiredEnergyWh: 147.0,
          estimatedEndSocPercent: 81.3,
        ),
      );

      expect(alt.distanceText, '4.2 km');
      expect(alt.durationText, '13 min');
      expect(alt.elevationText, '+45 m');
      expect(alt.label, 'Schnellste');
      expect(alt.socEstimationText, '81 % Rest (147 Wh)');
    });
  });
}
