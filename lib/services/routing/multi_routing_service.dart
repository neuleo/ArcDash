import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';
import 'package:arcdash/services/navigation/charging_station_service.dart';
import 'package:arcdash/services/navigation/navigation_engine.dart';
import 'package:arcdash/services/routing/osrm_routing_service.dart';
import 'package:arcdash/services/routing/brouter_routing_service.dart';
import 'package:arcdash/services/routing/valhalla_routing_service.dart';

/// A route alternative returned to the UI: the NavigationRoute plus the
/// concrete profile used, so the user can pick between backends.
class RouteAlternative {
  final RoutingProfile profile;
  final NavigationRoute route;
  final EnergyEstimationResult? energyEstimation;

  const RouteAlternative({
    required this.profile,
    required this.route,
    this.energyEstimation,
  });

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

  String get socEstimationText {
    if (energyEstimation == null) return '';
    final endSoc = energyEstimation!.estimatedEndSocPercent.round();
    final usedWh = energyEstimation!.requiredEnergyWh.round();
    return '$endSoc % Rest ($usedWh Wh)';
  }
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
  Future<List<RouteAlternative>> fetchAlternatives({
    required GeoLatLng origin,
    required GeoLatLng destination,
    List<GeoLatLng> waypoints = const [],
    double? batteryCapacityWh,
    double? socPercent,
    double? avgWhPerKm,
    bool autoInsertChargingStops = false,
    ChargingStationService? chargingStationService,
  }) async {
    final energyProfile = EnergyProfile(
      baseConsumptionWhPerKm: avgWhPerKm ?? 35.0,
      elevationGainWhPerMeter: 0.25,
      elevationLossRegenWhPerMeter: 0.05,
    );

    var effectiveWaypoints = List<GeoLatLng>.from(waypoints);

    // If autoInsertChargingStops is explicitly enabled and destination cannot be reached directly
    if (autoInsertChargingStops &&
        effectiveWaypoints.isEmpty &&
        chargingStationService != null &&
        batteryCapacityWh != null &&
        socPercent != null) {
      final approxDistKm =
          NavigationEngine.distanceBetween(origin, destination) / 1000.0;
      final totalEnergyAvailWh = batteryCapacityWh * (socPercent / 100.0);
      final estimatedNeedWh = approxDistKm * (avgWhPerKm ?? 35.0);
      if (estimatedNeedWh > (totalEnergyAvailWh * 0.9)) {
        // Find charging station around midpoint
        final midLat = (origin.latitude + destination.latitude) / 2.0;
        final midLon = (origin.longitude + destination.longitude) / 2.0;
        try {
          final pois = await chargingStationService.findNearbyCharging(
            center: GeoLatLng(latitude: midLat, longitude: midLon),
            radiusMeters: 20000,
          );
          if (pois.isNotEmpty) {
            effectiveWaypoints.add(pois.first.location);
          }
        } catch (_) {}
      }
    }

    RouteAlternative wrap(RoutingProfile profile, NavigationRoute route) {
      EnergyEstimationResult? estimation;
      if (batteryCapacityWh != null &&
          batteryCapacityWh > 0 &&
          socPercent != null) {
        final totalGain = route.elevationGainMetersTotal;
        final segment = RouteSegment(
          start: origin,
          end: destination,
          distanceMeters: route.totalDistanceMeters,
          startElevationMeters: 0,
          endElevationMeters: totalGain,
        );
        estimation = energyProfile.calculateEnergyNeed(
          segment: segment,
          currentBatteryCapacityWh: batteryCapacityWh,
          currentSocPercent: socPercent,
        );
      }
      return RouteAlternative(
        profile: profile,
        route: route,
        energyEstimation: estimation,
      );
    }

    final results = await Future.wait([
      _safe(() async {
        try {
          final r = await _brouter.calculateRoute(
            origin: origin,
            destination: destination,
            waypoints: effectiveWaypoints,
            preference: RoutingPreference.fastest,
          );
          return wrap(RoutingProfile.fastestCar, r);
        } catch (_) {
          final r = await _osrm.calculateRoute(
            origin: origin,
            destination: destination,
            waypoints: effectiveWaypoints,
          );
          return wrap(RoutingProfile.fastestCar, r);
        }
      }),
      _safe(() async {
        final r = await _brouter.calculateRoute(
          origin: origin,
          destination: destination,
          waypoints: effectiveWaypoints,
          preference: RoutingPreference.trailPreferred,
        );
        return wrap(RoutingProfile.trailForest, r);
      }),
      _safe(() async {
        final r = await _brouter.calculateRoute(
          origin: origin,
          destination: destination,
          waypoints: effectiveWaypoints,
          preference: RoutingPreference.avoidHighways,
        );
        return wrap(RoutingProfile.scenicTrekking, r);
      }),
      _safe(() => _ebikeRoute(origin, destination, effectiveWaypoints, wrap),
          timeout: const Duration(seconds: 12)),
    ]);

    return results.whereType<RouteAlternative>().toList(growable: false);
  }

  /// E-bike profile: Valhalla first (elevation-aware), OSRM fallback.
  Future<RouteAlternative> _ebikeRoute(
    GeoLatLng origin,
    GeoLatLng destination,
    List<GeoLatLng> waypoints,
    RouteAlternative Function(RoutingProfile, NavigationRoute) wrap,
  ) async {
    try {
      final r = await _valhalla.calculateRoute(
        origin: origin,
        destination: destination,
        waypoints: waypoints,
        preference: RoutingPreference.avoidHighways,
      );
      return wrap(RoutingProfile.ebikeOptimized, r);
    } catch (_) {
      final r = await _osrm.calculateRoute(
        origin: origin,
        destination: destination,
        waypoints: waypoints,
      );
      return wrap(RoutingProfile.ebikeOptimized, r);
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
