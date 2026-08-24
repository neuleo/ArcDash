library navigation_interfaces;

/// Domain models and interfaces for Version 2 Navigation, Routing, Elevation, and Energy estimation.
/// Keeps Version 1 range prediction decoupled from specific routing or mapping providers.

class GeoLatLng {
  final double latitude;
  final double longitude;

  const GeoLatLng({
    required this.latitude,
    required this.longitude,
  });
}

class RouteSegment {
  final GeoLatLng start;
  final GeoLatLng end;
  final double distanceMeters;
  final double startElevationMeters;
  final double endElevationMeters;
  final String surfaceType;

  const RouteSegment({
    required this.start,
    required this.end,
    required this.distanceMeters,
    this.startElevationMeters = 0.0,
    this.endElevationMeters = 0.0,
    this.surfaceType = 'paved',
  });

  double get elevationGainMeters {
    final delta = endElevationMeters - startElevationMeters;
    return delta > 0 ? delta : 0.0;
  }

  double get elevationLossMeters {
    final delta = startElevationMeters - endElevationMeters;
    return delta > 0 ? delta : 0.0;
  }
}

enum RoutingPreference {
  fastest,
  shortest,
  avoidHighways,
  trailPreferred,
}

/// Concrete routing backends mapped from [RoutingPreference] by
/// RoutingProviderFactory. Each maps to a free, key-less community service
/// (see plan/16-map-navigation.md).
enum RoutingProfile {
  /// OSRM routed-car — fastest road route.
  fastestCar,

  /// BRouter mtb — prefers forest tracks / unpaved paths.
  trailForest,

  /// BRouter trekking — scenic, balanced surface mix.
  scenicTrekking,

  /// Valhalla bicycle+Mountain — elevation-aware costing.
  ebikeOptimized,
}

extension RoutingProfileX on RoutingProfile {
  String get label => switch (this) {
        RoutingProfile.fastestCar => 'Schnellste',
        RoutingProfile.trailForest => 'Wald & Trail',
        RoutingProfile.scenicTrekking => 'Scenic',
        RoutingProfile.ebikeOptimized => 'E-Bike optimiert',
      };

  String get providerName => switch (this) {
        RoutingProfile.fastestCar => 'OSRM',
        RoutingProfile.trailForest ||
        RoutingProfile.scenicTrekking =>
          'BRouter',
        RoutingProfile.ebikeOptimized => 'Valhalla',
      };
}

/// A turn-by-turn navigation step / instruction along a route.
class RouteManeuver {
  final String instruction;
  final double distanceMeters;
  final GeoLatLng? location;
  final String? modifier; // 'left', 'right', 'slight right', etc.
  final String? type; // 'turn', 'depart', 'arrive', etc.

  const RouteManeuver({
    required this.instruction,
    required this.distanceMeters,
    this.location,
    this.modifier,
    this.type,
  });
}

class NavigationRoute {
  final List<RouteSegment> segments;
  final double totalDistanceMeters;
  final RoutingPreference preference;

  /// Full polyline geometry (route shape) for map rendering.
  final List<GeoLatLng> geometry;

  /// Total estimated travel time in seconds.
  final double durationSeconds;

  /// Cumulative ascent in meters (when provider reports it).
  final double elevationGainMetersTotal;

  /// Which free service computed this route ('OSRM' | 'BRouter' | 'Valhalla').
  final String providerName;

  /// Turn-by-turn maneuvers along the route.
  final List<RouteManeuver> maneuvers;

  const NavigationRoute({
    required this.segments,
    required this.totalDistanceMeters,
    required this.preference,
    this.geometry = const [],
    this.durationSeconds = 0,
    this.elevationGainMetersTotal = 0,
    this.providerName = '',
    this.maneuvers = const [],
  });
}

class EnergyEstimationResult {
  final double requiredEnergyWh;
  final double estimatedEndSocPercent;

  const EnergyEstimationResult({
    required this.requiredEnergyWh,
    required this.estimatedEndSocPercent,
  });
}

class EnergyProfile {
  final double baseConsumptionWhPerKm;
  final double elevationGainWhPerMeter;
  final double elevationLossRegenWhPerMeter;

  const EnergyProfile({
    this.baseConsumptionWhPerKm = 30.0,
    this.elevationGainWhPerMeter = 0.20,
    this.elevationLossRegenWhPerMeter = 0.05,
  });

  EnergyEstimationResult calculateEnergyNeed({
    required RouteSegment segment,
    required double currentBatteryCapacityWh,
    required double currentSocPercent,
  }) {
    final distanceKm = segment.distanceMeters / 1000.0;
    final baseEnergy = distanceKm * baseConsumptionWhPerKm;
    final elevationGainEnergy =
        segment.elevationGainMeters * elevationGainWhPerMeter;
    final elevationLossRegen =
        segment.elevationLossMeters * elevationLossRegenWhPerMeter;

    final netEnergyNeeded =
        (baseEnergy + elevationGainEnergy - elevationLossRegen)
            .clamp(0.0, double.infinity);

    final currentEnergyWh =
        (currentSocPercent / 100.0) * currentBatteryCapacityWh;
    final remainingEnergyWh = currentEnergyWh - netEnergyNeeded;

    final endSoc = currentBatteryCapacityWh > 0
        ? (remainingEnergyWh / currentBatteryCapacityWh) * 100.0
        : 0.0;

    return EnergyEstimationResult(
      requiredEnergyWh: netEnergyNeeded,
      estimatedEndSocPercent: endSoc,
    );
  }
}

abstract class RoutingService {
  Future<NavigationRoute> calculateRoute({
    required GeoLatLng origin,
    required GeoLatLng destination,
    RoutingPreference preference = RoutingPreference.fastest,
  });
}

abstract class ElevationService {
  Future<double> getElevation(GeoLatLng location);
}

class FakeRoutingService implements RoutingService {
  @override
  Future<NavigationRoute> calculateRoute({
    required GeoLatLng origin,
    required GeoLatLng destination,
    RoutingPreference preference = RoutingPreference.fastest,
  }) async {
    final segment = RouteSegment(
      start: origin,
      end: destination,
      distanceMeters: 5000.0,
      startElevationMeters: 100.0,
      endElevationMeters: 150.0,
      surfaceType:
          preference == RoutingPreference.trailPreferred ? 'unpaved' : 'paved',
    );

    return NavigationRoute(
      segments: [segment],
      totalDistanceMeters: 5000.0,
      preference: preference,
    );
  }
}

class FakeElevationService implements ElevationService {
  @override
  Future<double> getElevation(GeoLatLng location) async {
    return 120.0;
  }
}
