import 'dart:math' as math;

import 'package:arcdash/domain/navigation/navigation_interfaces.dart';
import 'package:arcdash/services/gps_service.dart';

/// Progress state along an active navigation route.
class NavigationProgress {
  final int currentManeuverIndex;
  final double distanceToNextManeuverMeters;
  final double remainingDistanceMeters;
  final double remainingDurationSeconds;
  final bool isOffRoute;
  final double currentBearingDeg;

  const NavigationProgress({
    required this.currentManeuverIndex,
    required this.distanceToNextManeuverMeters,
    required this.remainingDistanceMeters,
    required this.remainingDurationSeconds,
    this.isOffRoute = false,
    this.currentBearingDeg = 0.0,
  });
}

/// Computes live progress along a polyline geometry and list of maneuvers.
class NavigationEngine {
  static const double _kManeuverAdvanceThresholdMeters = 35.0;
  static const double _kOffRouteThresholdMeters = 60.0;

  /// Haversine distance in meters between two lat/lon points.
  static double distanceBetween(GeoLatLng a, GeoLatLng b) {
    const r = 6371000.0; // Earth radius in meters
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);

    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLon / 2) *
            math.sin(dLon / 2) *
            math.cos(lat1) *
            math.cos(lat2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return r * c;
  }

  /// Calculates bearing from point a to point b in degrees [0..360].
  static double bearingBetween(GeoLatLng a, GeoLatLng b) {
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = math.atan2(y, x);
    return (_rad2deg(brng) + 360.0) % 360.0;
  }

  /// Updates progress for [currentFix] along [route] given [currentIndex].
  static NavigationProgress evaluateProgress({
    required NavigationRoute route,
    required GpsFix currentFix,
    required int currentIndex,
  }) {
    if (route.maneuvers.isEmpty) {
      return NavigationProgress(
        currentManeuverIndex: 0,
        distanceToNextManeuverMeters: route.totalDistanceMeters,
        remainingDistanceMeters: route.totalDistanceMeters,
        remainingDurationSeconds: route.durationSeconds,
      );
    }

    final userLoc = GeoLatLng(
        latitude: currentFix.latitude, longitude: currentFix.longitude);

    // Find distance to closest point on polyline to detect off-route
    double minPolyDist = double.infinity;
    for (final pt in route.geometry) {
      final d = distanceBetween(userLoc, pt);
      if (d < minPolyDist) minPolyDist = d;
    }
    final isOffRoute = minPolyDist > _kOffRouteThresholdMeters;

    var newIndex = currentIndex;
    final currentManeuver = route.maneuvers[newIndex];
    double distToNext = currentManeuver.distanceMeters;

    if (currentManeuver.location != null) {
      distToNext = distanceBetween(userLoc, currentManeuver.location!);
      if (distToNext < _kManeuverAdvanceThresholdMeters &&
          newIndex < route.maneuvers.length - 1) {
        newIndex++;
      }
    }

    // Calculate approximate remaining distance from current maneuver to end
    double remDist = 0.0;
    for (int i = newIndex; i < route.maneuvers.length; i++) {
      remDist += route.maneuvers[i].distanceMeters;
    }

    final avgSpeedMs =
        route.totalDistanceMeters > 0 && route.durationSeconds > 0
            ? (route.totalDistanceMeters / route.durationSeconds)
            : 10.0; // fallback 36 km/h
    final remDuration = remDist / avgSpeedMs;

    return NavigationProgress(
      currentManeuverIndex: newIndex,
      distanceToNextManeuverMeters: distToNext,
      remainingDistanceMeters: remDist,
      remainingDurationSeconds: remDuration,
      isOffRoute: isOffRoute,
    );
  }

  static double _deg2rad(double deg) => deg * (math.pi / 180.0);
  static double _rad2deg(double rad) => rad * (180.0 / math.pi);
}
