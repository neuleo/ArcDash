import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';
import 'package:arcdash/services/gps_service.dart';
import 'package:arcdash/services/routing/multi_routing_service.dart';

/// State of the map screen: origin, destination, alternatives, selection, navigation active.
class MapState {
  final GeoLatLng? origin;
  final String? originLabel;
  final GeoLatLng? destination;
  final String? destinationLabel;
  final List<RouteAlternative> alternatives;
  final RouteAlternative? selected;
  final bool isNavigating;
  final int currentManeuverIndex;
  final double? estimatedRangeKm;

  const MapState({
    this.origin,
    this.originLabel,
    this.destination,
    this.destinationLabel,
    this.alternatives = const [],
    this.selected,
    this.isNavigating = false,
    this.currentManeuverIndex = 0,
    this.estimatedRangeKm,
  });

  MapState copyWith({
    GeoLatLng? origin,
    String? originLabel,
    bool clearOrigin = false,
    GeoLatLng? destination,
    String? destinationLabel,
    List<RouteAlternative>? alternatives,
    RouteAlternative? selected,
    bool clearSelected = false,
    bool? isNavigating,
    int? currentManeuverIndex,
    double? estimatedRangeKm,
  }) =>
      MapState(
        origin: clearOrigin ? null : (origin ?? this.origin),
        originLabel: clearOrigin ? null : (originLabel ?? this.originLabel),
        destination: destination ?? this.destination,
        destinationLabel: destinationLabel ?? this.destinationLabel,
        alternatives: alternatives ?? this.alternatives,
        selected: clearSelected ? null : (selected ?? this.selected),
        isNavigating: isNavigating ?? this.isNavigating,
        currentManeuverIndex: currentManeuverIndex ?? this.currentManeuverIndex,
        estimatedRangeKm: estimatedRangeKm ?? this.estimatedRangeKm,
      );
}

class MapStateNotifier extends StateNotifier<MapState> {
  MapStateNotifier(this._ref, {bool autoInitGps = true})
      : super(const MapState()) {
    if (autoInitGps) {
      _initGps();
    }
  }

  final Ref? _ref;
  StreamSubscription<GpsFix>? _gpsSub;

  void _initGps() {
    if (_ref == null) return;
    try {
      final gpsService = _ref.read(gpsServiceProvider);
      gpsService.start().then((started) {
        if (started) {
          _gpsSub = gpsService.stream.listen((fix) {
            if (fix.isValid) {
              final newOrigin =
                  GeoLatLng(latitude: fix.latitude, longitude: fix.longitude);
              state = state.copyWith(
                origin: newOrigin,
                originLabel: 'Mein Standort',
              );
            }
          });
        }
      }).catchError((_) {
        // MissingPluginException in widget test / background execution
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    super.dispose();
  }

  void setEstimatedRangeKm(double km) {
    state = state.copyWith(estimatedRangeKm: km);
  }

  void setDestination(GeoLatLng point, {String? label}) {
    state = state.copyWith(
      destination: point,
      destinationLabel: label ?? 'Gewählter Punkt',
      clearSelected: true,
      alternatives: const [],
      isNavigating: false,
      currentManeuverIndex: 0,
    );
  }

  void setDestinationFromTap(double lat, double lon) {
    setDestination(GeoLatLng(latitude: lat, longitude: lon),
        label: 'Karten-Punkt');
  }

  Future<void> useCurrentLocationAsOrigin() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 8));
      state = state.copyWith(
        origin: GeoLatLng(latitude: pos.latitude, longitude: pos.longitude),
        originLabel: 'Mein Standort',
      );
    } catch (_) {
      // GPS unavailable — ignore.
    }
  }

  void setAlternatives(List<RouteAlternative> alts) {
    state = state.copyWith(alternatives: alts);
  }

  void selectAlternative(RouteAlternative a) {
    state = state.copyWith(
      selected: a,
      isNavigating: false,
      currentManeuverIndex: 0,
    );
  }

  void startNavigation() {
    if (state.selected != null) {
      state = state.copyWith(
        isNavigating: true,
        currentManeuverIndex: 0,
      );
    }
  }

  void stopNavigation() {
    state = state.copyWith(isNavigating: false);
  }

  void nextManeuver() {
    if (state.selected != null &&
        state.currentManeuverIndex <
            state.selected!.route.maneuvers.length - 1) {
      state = state.copyWith(
        currentManeuverIndex: state.currentManeuverIndex + 1,
      );
    }
  }

  void prevManeuver() {
    if (state.currentManeuverIndex > 0) {
      state = state.copyWith(
        currentManeuverIndex: state.currentManeuverIndex - 1,
      );
    }
  }

  void clearRoute() {
    state = MapState(
      origin: state.origin,
      originLabel: state.originLabel,
      estimatedRangeKm: state.estimatedRangeKm,
    );
  }
}

final mapControllerProvider = StateNotifierProvider<MapStateNotifier, MapState>(
    (ref) => MapStateNotifier(ref));
