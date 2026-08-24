import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';
import 'package:arcdash/models/map_favorite.dart';
import 'package:arcdash/providers/map_provider.dart';
import 'package:arcdash/services/routing/osrm_routing_service.dart';
import 'package:arcdash/services/routing/brouter_routing_service.dart';
import 'package:arcdash/services/routing/valhalla_routing_service.dart';
import 'package:arcdash/services/routing/multi_routing_service.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

http.Response _ok(String body) =>
    http.Response(body, 200, headers: {'content-type': 'application/json'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Point of No Return & Auto-Charging in MapStateNotifier', () {
    test('togglePointOfNoReturn and toggleAutoChargingStops update state', () {
      final c = MapStateNotifier(null, autoInitGps: false);
      expect(c.state.pointOfNoReturnEnabled, isTrue);
      expect(c.state.autoChargingStopsEnabled, isFalse);

      c.togglePointOfNoReturn();
      expect(c.state.pointOfNoReturnEnabled, isFalse);

      c.toggleAutoChargingStops();
      expect(c.state.autoChargingStopsEnabled, isTrue);
    });

    test(
        'MultiRoutingService fetchAlternatives respects autoInsertChargingStops parameter',
        () async {
      final osrm = OsrmRoutingService(
        client: MockClient((_) async => _ok(fixture('osrm_route.json'))),
      );
      final brouter = BRouterRoutingService(
        client: MockClient((_) async => _ok(fixture('brouter_mtb.geojson'))),
      );
      final valhalla = ValhallaRoutingService(
        client: MockClient((_) async => _ok(fixture('valhalla_route.json'))),
      );

      final multi = MultiRoutingService(
        osrm: osrm,
        brouter: brouter,
        valhalla: valhalla,
      );

      const origin = GeoLatLng(latitude: 52.5170, longitude: 13.3888);
      const destination = GeoLatLng(latitude: 52.5223, longitude: 13.3976);

      // Should run safely with autoInsertChargingStops = false
      final alts = await multi.fetchAlternatives(
        origin: origin,
        destination: destination,
        batteryCapacityWh: 3800,
        socPercent: 90,
        autoInsertChargingStops: false,
      );

      expect(alts, isNotEmpty);
      multi.dispose();
    });
  });
}
