import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';
import 'package:arcdash/services/routing/osrm_routing_service.dart';
import 'package:arcdash/services/routing/brouter_routing_service.dart';
import 'package:arcdash/services/routing/valhalla_routing_service.dart';

/// A route alternative returned to the UI: the NavigationRoute plus the
/// concrete profile used, so the user can pick between backends.
class RouteAlternative {
  final RoutingProfile profile;
  final NavigationRoute route;

  const RouteAlternative({required this.profile, required this.route});

  String get label => profile.label;
  String get provider => route.providerName;

  String get distanceText {
    final km = route.totalDistanceMeters / 1000;
    return km >= 10 ? '${km.round()} km' : '${km.toStringAsFixed(1)} km';
  }

  String get durationText {
    final min = (route.durationSeconds / 60).round();
    if (min < 60) return '$min min';
    return '${min ~/ 60} h ${min % 60} min';
  }

  String get elevationText => route.elevationGainMetersTotal > 0
      ? '+${route.elevationGainMetersTotal.round()} m'
      : '';
}

/// Computes all available alternatives for a trip across the free providers.
/// Each profile is computed independently; failures degrade gracefully.
class MultiRoutingService {
  MultiRoutingService({
    OsrmRoutingService? osrm,
    BRouterRoutingService? brouter,
    ValhallaRoutingService? valhalla,
  })  : _osrm = osrm ?? OsrmRoutingService(),
        _brouter = brouter ?? BRouterRoutingService(),
        _valhalla = valhalla ?? ValhallaRoutingService();

  final OsrmRoutingService _osrm;
  final BRouterRoutingService _brouter;
  final ValhallaRoutingService _valhalla;

  /// All four profiles in parallel; returns whatever succeeded (≥1).
  ///
  /// Valhalla is the slowest/flakiest community endpoint — we give it a head
  /// start via its own shorter window and fall back to an OSRM-based
  /// "ebike" alternative so the sheet still shows 4 options.
  Future<List<RouteAlternative>> fetchAlternatives({
    required GeoLatLng origin,
    required GeoLatLng destination,
  }) async {
    final results = await Future.wait([
      _safe(() async {
        final r = await _osrm.calculateRoute(
            origin: origin, destination: destination);
        return RouteAlternative(profile: RoutingProfile.fastestCar, route: r);
      }),
      _safe(() async {
        final r = await _brouter.calculateRoute(
            origin: origin,
            destination: destination,
            preference: RoutingPreference.trailPreferred);
        return RouteAlternative(profile: RoutingProfile.trailForest, route: r);
      }),
      _safe(() async {
        final r = await _brouter.calculateRoute(
            origin: origin,
            destination: destination,
            preference: RoutingPreference.avoidHighways);
        return RouteAlternative(
            profile: RoutingProfile.scenicTrekking, route: r);
      }),
      _safe(() => _ebikeRoute(origin, destination),
          timeout: const Duration(seconds: 12)),
    ]);

    return results.whereType<RouteAlternative>().toList(growable: false);
  }

  /// E-bike profile: Valhalla first (elevation-aware), OSRM fallback.
  Future<RouteAlternative> _ebikeRoute(
      GeoLatLng origin, GeoLatLng destination) async {
    try {
      final r = await _valhalla.calculateRoute(
          origin: origin,
          destination: destination,
          preference: RoutingPreference.avoidHighways);
      return RouteAlternative(profile: RoutingProfile.ebikeOptimized, route: r);
    } catch (_) {
      final r =
          await _osrm.calculateRoute(origin: origin, destination: destination);
      return RouteAlternative(profile: RoutingProfile.ebikeOptimized, route: r);
    }
  }

  Future<RouteAlternative?> _safe(
    Future<RouteAlternative> Function() fn, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    try {
      return await fn().timeout(timeout);
    } catch (_) {
      return null; // provider down / no coverage — skip silently
    }
  }

  void dispose() {
    _osrm.dispose();
    _brouter.dispose();
    _valhalla.dispose();
  }
}

final multiRoutingServiceProvider =
    Provider<MultiRoutingService>((ref) => MultiRoutingService());
