import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';
import 'package:arcdash/models/map_favorite.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/demo_controller_provider.dart';
import 'package:arcdash/providers/demo_mode_provider.dart';
import 'package:arcdash/services/gps_service.dart';
import 'package:arcdash/services/navigation/learned_energy_model.dart';
import 'package:arcdash/services/navigation/map_favorites_repository.dart';
import 'package:arcdash/services/navigation/navigation_engine.dart';
import 'package:arcdash/services/routing/multi_routing_service.dart';

enum MapPerspective { northUp, headUp }

/// State of the map screen: origin, destination, alternatives, selection, navigation active,
/// perspective (3D/Head-Up vs North-Up), user zoom preferences, custom planning SOC.
class MapState {
  final GeoLatLng? origin;
  final String? originLabel;
  final GeoLatLng? destination;
  final String? destinationLabel;
  final List<GeoLatLng> waypoints;
  final List<RouteAlternative> alternatives;
  final RouteAlternative? selected;
  final bool isNavigating;
  final int currentManeuverIndex;
  final double? estimatedRangeKm;
  final MapPerspective perspective;
  final double userZoom;
  final bool autoFollowUser;
  final double? planningStartSocOverride;
  final List<MapFavorite> favorites;
  final List<MapFavorite> recents;
  final double currentHeadingDeg;
  final bool isRoundTrip;
  final bool pointOfNoReturnEnabled;
  final bool autoChargingStopsEnabled;
  final bool pointOfNoReturnTriggered;
  final double neededReturnSocPercent;
  final GeoLatLng? sessionStartingPoint;

  const MapState({
    this.origin,
    this.originLabel,
    this.destination,
    this.destinationLabel,
    this.waypoints = const [],
    this.alternatives = const [],
    this.selected,
    this.isNavigating = false,
    this.currentManeuverIndex = 0,
    this.estimatedRangeKm,
    this.perspective = MapPerspective.northUp,
    this.userZoom = 14.0,
    this.autoFollowUser = true,
    this.planningStartSocOverride,
    this.favorites = const [],
    this.recents = const [],
    this.currentHeadingDeg = 0.0,
    this.isRoundTrip = false,
    this.pointOfNoReturnEnabled = true,
    this.autoChargingStopsEnabled = false,
    this.pointOfNoReturnTriggered = false,
    this.neededReturnSocPercent = 0.0,
    this.sessionStartingPoint,
  });

  MapState copyWith({
    GeoLatLng? origin,
    String? originLabel,
    bool clearOrigin = false,
    GeoLatLng? destination,
    String? destinationLabel,
    List<GeoLatLng>? waypoints,
    List<RouteAlternative>? alternatives,
    RouteAlternative? selected,
    bool clearSelected = false,
    bool? isNavigating,
    int? currentManeuverIndex,
    double? estimatedRangeKm,
    MapPerspective? perspective,
    double? userZoom,
    bool? autoFollowUser,
    double? planningStartSocOverride,
    bool clearSocOverride = false,
    List<MapFavorite>? favorites,
    List<MapFavorite>? recents,
    double? currentHeadingDeg,
    bool? isRoundTrip,
    bool? pointOfNoReturnEnabled,
    bool? autoChargingStopsEnabled,
    bool? pointOfNoReturnTriggered,
    double? neededReturnSocPercent,
    GeoLatLng? sessionStartingPoint,
  }) =>
      MapState(
        origin: clearOrigin ? null : (origin ?? this.origin),
        originLabel: clearOrigin ? null : (originLabel ?? this.originLabel),
        destination: destination ?? this.destination,
        destinationLabel: destinationLabel ?? this.destinationLabel,
        waypoints: waypoints ?? this.waypoints,
        alternatives: alternatives ?? this.alternatives,
        selected: clearSelected ? null : (selected ?? this.selected),
        isNavigating: isNavigating ?? this.isNavigating,
        currentManeuverIndex: currentManeuverIndex ?? this.currentManeuverIndex,
        estimatedRangeKm: estimatedRangeKm ?? this.estimatedRangeKm,
        perspective: perspective ?? this.perspective,
        userZoom: userZoom ?? this.userZoom,
        autoFollowUser: autoFollowUser ?? this.autoFollowUser,
        planningStartSocOverride: clearSocOverride
            ? null
            : (planningStartSocOverride ?? this.planningStartSocOverride),
        favorites: favorites ?? this.favorites,
        recents: recents ?? this.recents,
        currentHeadingDeg: currentHeadingDeg ?? this.currentHeadingDeg,
        isRoundTrip: isRoundTrip ?? this.isRoundTrip,
        pointOfNoReturnEnabled:
            pointOfNoReturnEnabled ?? this.pointOfNoReturnEnabled,
        autoChargingStopsEnabled:
            autoChargingStopsEnabled ?? this.autoChargingStopsEnabled,
        pointOfNoReturnTriggered:
            pointOfNoReturnTriggered ?? this.pointOfNoReturnTriggered,
        neededReturnSocPercent:
            neededReturnSocPercent ?? this.neededReturnSocPercent,
        sessionStartingPoint: sessionStartingPoint ?? this.sessionStartingPoint,
      );
}

final mapFavoritesRepositoryProvider = Provider<MapFavoritesRepository>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return MapFavoritesRepository(storage: storage.rangePredictionStorage);
});

class MapStateNotifier extends StateNotifier<MapState> {
  MapStateNotifier(this._ref, {bool autoInitGps = true})
      : super(const MapState()) {
    _loadFavoritesAndRecents();
    if (autoInitGps) {
      _initGps();
    }
  }

  final Ref? _ref;
  StreamSubscription<GpsFix>? _gpsSub;

  void _loadFavoritesAndRecents() {
    if (_ref == null) return;
    try {
      final repo = _ref.read(mapFavoritesRepositoryProvider);
      state = state.copyWith(
        favorites: repo.loadFavorites(),
        recents: repo.loadRecents(),
      );
    } catch (_) {}
  }

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

              // Live Navigation progress & Heading calculation
              var nextIndex = state.currentManeuverIndex;
              var heading = state.currentHeadingDeg;

              if (state.origin != null) {
                final d =
                    NavigationEngine.distanceBetween(state.origin!, newOrigin);
                if (d > 2.0) {
                  heading =
                      NavigationEngine.bearingBetween(state.origin!, newOrigin);
                }
              }

              if (state.isNavigating && state.selected != null) {
                final progress = NavigationEngine.evaluateProgress(
                  route: state.selected!.route,
                  currentFix: fix,
                  currentIndex: state.currentManeuverIndex,
                );
                nextIndex = progress.currentManeuverIndex;
              }

              final startPoint = state.sessionStartingPoint ?? newOrigin;

              // Point of No Return evaluation (Smart Home Return Buffer)
              var ponrTriggered = false;
              var neededReturnSoc = 0.0;
              if (state.pointOfNoReturnEnabled && _ref != null) {
                try {
                  final homeFav = state.favorites
                      .where((f) => f.type == FavoriteType.home)
                      .firstOrNull;
                  final basePoint = homeFav?.location ?? startPoint;
                  final distKm =
                      NavigationEngine.distanceBetween(newOrigin, basePoint) /
                          1000.0;
                  if (distKm > 1.0) {
                    final learnedModel = _ref.read(learnedEnergyModelProvider);
                    final ctrl = _ref.read(effectiveControllerProvider);
                    final bms = _ref.read(effectiveBmsProvider);
                    final curSoc = state.planningStartSocOverride ??
                        (bms?.socPercent?.toDouble() ??
                            (ctrl.battCapPercent > 0
                                ? ctrl.battCapPercent.toDouble()
                                : 85.0));

                    final energyNeedWh =
                        distKm * 1.35 * learnedModel.baseWhPerKm;
                    final socNeed =
                        (energyNeedWh / learnedModel.learnedCapacityWh) * 100.0;
                    neededReturnSoc = (socNeed + 10.0).clamp(0.0, 100.0);

                    if (curSoc <= neededReturnSoc) {
                      ponrTriggered = true;
                    }
                  }
                } catch (_) {}
              }

              state = state.copyWith(
                origin: newOrigin,
                originLabel: 'Mein Standort',
                sessionStartingPoint: startPoint,
                currentManeuverIndex: nextIndex,
                currentHeadingDeg: heading,
                pointOfNoReturnTriggered: ponrTriggered,
                neededReturnSocPercent: neededReturnSoc,
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

  void setPlanningStartSoc(double? soc) {
    if (soc == null) {
      state = state.copyWith(clearSocOverride: true);
    } else {
      state = state.copyWith(planningStartSocOverride: soc);
    }
  }

  void togglePerspective() {
    final next = state.perspective == MapPerspective.northUp
        ? MapPerspective.headUp
        : MapPerspective.northUp;
    state = state.copyWith(perspective: next);
  }

  void togglePointOfNoReturn() {
    state = state.copyWith(
      pointOfNoReturnEnabled: !state.pointOfNoReturnEnabled,
    );
  }

  void toggleAutoChargingStops() {
    state = state.copyWith(
      autoChargingStopsEnabled: !state.autoChargingStopsEnabled,
    );
  }

  void setUserZoom(double zoom) {
    state = state.copyWith(userZoom: zoom);
  }

  void setAutoFollow(bool follow) {
    state = state.copyWith(autoFollowUser: follow);
  }

  void addFavorite(MapFavorite favorite) {
    final favs = List<MapFavorite>.from(state.favorites);
    favs.removeWhere((e) => e.id == favorite.id || e.title == favorite.title);
    favs.insert(0, favorite);
    if (_ref != null) {
      final repo = _ref.read(mapFavoritesRepositoryProvider);
      repo.saveFavorites(favs);
    }
    state = state.copyWith(favorites: favs);
  }

  void updateFavorite(MapFavorite favorite) {
    final favs = List<MapFavorite>.from(state.favorites);
    final idx = favs.indexWhere((e) => e.id == favorite.id);
    if (idx >= 0) {
      favs[idx] = favorite;
    } else {
      favs.insert(0, favorite);
    }
    if (_ref != null) {
      final repo = _ref.read(mapFavoritesRepositoryProvider);
      repo.saveFavorites(favs);
    }
    state = state.copyWith(favorites: favs);
  }

  void removeFavorite(String id) {
    final favs = List<MapFavorite>.from(state.favorites)
      ..removeWhere((e) => e.id == id);
    if (_ref != null) {
      final repo = _ref.read(mapFavoritesRepositoryProvider);
      repo.saveFavorites(favs);
    }
    state = state.copyWith(favorites: favs);
  }

  void addRecent(MapFavorite recent) {
    // Never duplicate an existing favorite in recents
    final isAlreadyFavorite = state.favorites.any((f) =>
        f.title.toLowerCase() == recent.title.toLowerCase() ||
        (f.location.latitude == recent.location.latitude &&
            f.location.longitude == recent.location.longitude));
    if (isAlreadyFavorite) return;

    if (_ref != null) {
      final repo = _ref.read(mapFavoritesRepositoryProvider);
      repo.addRecent(recent);
      state = state.copyWith(recents: repo.loadRecents());
    } else {
      final recs = List<MapFavorite>.from(state.recents)
        ..removeWhere((r) => r.title == recent.title)
        ..insert(0, recent);
      state = state.copyWith(recents: recs.take(5).toList());
    }
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
    if (label != null && label.isNotEmpty) {
      addRecent(MapFavorite(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: label,
        location: point,
        type: FavoriteType.recent,
        createdAt: DateTime.now(),
      ));
    }
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
        autoFollowUser: true,
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
        autoFollowUser: true,
        perspective: MapPerspective.headUp,
      );
    }
  }

  void stopNavigation() {
    state = state.copyWith(
      isNavigating: false,
      perspective: MapPerspective.northUp,
    );
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

  void addWaypoint(GeoLatLng point) {
    final wps = List<GeoLatLng>.from(state.waypoints)..add(point);
    state = state.copyWith(
      waypoints: wps,
      clearSelected: true,
      alternatives: const [],
    );
  }

  void removeWaypoint(int index) {
    if (index >= 0 && index < state.waypoints.length) {
      final wps = List<GeoLatLng>.from(state.waypoints)..removeAt(index);
      state = state.copyWith(
        waypoints: wps,
        clearSelected: true,
        alternatives: const [],
      );
    }
  }

  void toggleRoundTrip() {
    final next = !state.isRoundTrip;
    state = state.copyWith(
      isRoundTrip: next,
      clearSelected: true,
      alternatives: const [],
    );
  }

  void clearRoute() {
    state = MapState(
      origin: state.origin,
      originLabel: state.originLabel,
      estimatedRangeKm: state.estimatedRangeKm,
      favorites: state.favorites,
      recents: state.recents,
      waypoints: const [],
      isRoundTrip: false,
    );
  }
}

final mapControllerProvider = StateNotifierProvider<MapStateNotifier, MapState>(
    (ref) => MapStateNotifier(ref));
