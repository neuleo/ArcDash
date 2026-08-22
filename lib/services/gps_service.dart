import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// One GPS fix with altitude (needed for elevation-gain learning).
class GpsFix {
  final double latitude;
  final double longitude;
  final double altitudeMeters;
  final double accuracyMeters;
  final double speedKph;
  final DateTime at;

  const GpsFix({
    required this.latitude,
    required this.longitude,
    required this.altitudeMeters,
    required this.accuracyMeters,
    required this.speedKph,
    required this.at,
  });

  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      accuracyMeters <= 30.0 &&
      accuracyMeters > 0;

  Map<String, dynamic> toJson() => {
        'lat': latitude,
        'lon': longitude,
        'alt': altitudeMeters,
        'acc': accuracyMeters,
        'spd': speedKph,
        'at': at.toIso8601String(),
      };

  factory GpsFix.fromJson(Map<String, dynamic> j) => GpsFix(
        latitude: (j['lat'] as num).toDouble(),
        longitude: (j['lon'] as num).toDouble(),
        altitudeMeters: (j['alt'] as num).toDouble(),
        accuracyMeters: (j['acc'] as num).toDouble(),
        speedKph: (j['spd'] as num?)?.toDouble() ?? 0,
        at: DateTime.parse(j['at'] as String),
      );
}

/// Streams GPS fixes while the app runs. Permission is requested lazily on
/// the first [start] call; a denied permission results in an idle stream
/// without crashing — the ride log simply records null GPS.
class GpsService {
  StreamSubscription<Position>? _sub;
  final _controller = StreamController<GpsFix>.broadcast();
  bool _permissionGranted = false;

  Stream<GpsFix> get stream => _controller.stream;
  bool get isRunning => _sub != null;

  Future<bool> ensurePermission() async {
    if (_permissionGranted) return true;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    _permissionGranted = true;
    return true;
  }

  /// Starts streaming at ~1 Hz (matching the ride-log grid).
  Future<bool> start() async {
    if (_sub != null) return true;
    if (!await ensurePermission()) return false;

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0, // time-based, we sample ~1 Hz
      ),
    ).listen(
      (pos) {
        final fix = GpsFix(
          latitude: pos.latitude,
          longitude: pos.longitude,
          altitudeMeters: pos.altitude,
          accuracyMeters: pos.accuracy,
          speedKph: (pos.speed ?? 0) * 3.6,
          at: pos.timestamp ?? DateTime.now(),
        );
        if (fix.isValid) _controller.add(fix);
      },
      onError: (_) {/* keep stream alive; next fix may be valid */},
    );
    return true;
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  /// Latest known fix, or null.
  Future<GpsFix?> lastKnown() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos == null) return null;
      return GpsFix(
        latitude: pos.latitude,
        longitude: pos.longitude,
        altitudeMeters: pos.altitude,
        accuracyMeters: pos.accuracy,
        speedKph: (pos.speed ?? 0) * 3.6,
        at: pos.timestamp ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// App-wide singleton provider.
final gpsServiceProvider = Provider<GpsService>((ref) {
  final service = GpsService();
  ref.onDispose(service.stop);
  return service;
});
