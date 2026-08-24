import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:arcdash/domain/navigation/navigation_interfaces.dart';
import 'package:arcdash/models/map_favorite.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/demo_controller_provider.dart';
import 'package:arcdash/providers/demo_mode_provider.dart';
import 'package:arcdash/providers/map_provider.dart';
import 'package:arcdash/services/geocoding/geocoding_service.dart';
import 'package:arcdash/services/navigation/charging_station_service.dart';
import 'package:arcdash/services/navigation/learned_energy_model.dart';
import 'package:arcdash/services/routing/multi_routing_service.dart';
import 'package:arcdash/widgets/map_cockpit_hud.dart';
import 'package:arcdash/widgets/route_elevation_chart.dart';

final chargingStationServiceProvider =
    Provider<ChargingStationService>((ref) => ChargingStationService());

/// Comprehensive E-Moto Navigation & Trip Planning Screen:
/// - Landscape UX: Floating controls, no bulky top bar, bottom-left compact card
/// - Multi-Stop Waypoint system & 'Zurück zum Start' Roundtrip
/// - 4 Multi-Provider Routes (Fastest, Trail/Forest, Scenic, E-Bike)
/// - Self-learning Energy & Range estimation
/// - Tour Planner with Start-SOC Slider override
/// - Favorites (Home, Work, Custom) & Quick Recents
/// - 3D / Head-Up Perspective Lock with smooth Auto-Follow & Custom Zoom
/// - Turn-by-Turn Guidance Banner
/// - Live Cockpit HUD Overlay on Map
/// - 3-Zone Range Heatmap circles
/// - 230V Schuko & EV Charging POI Finder
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<GeoSearchResult> _results = [];
  List<ChargingStationPoi> _chargingStations = [];
  bool _searching = false;
  bool _routing = false;
  bool _loadingPois = false;
  bool _isSatellite = false;
  bool _hasInitialCentered = false;
  bool _showChargingStations = false;
  bool _showTourPlanner = false;
  bool _showWaypointsPanel = false;
  double _customStartSoc = 100.0;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (q.trim().length < 3) {
        setState(() => _results = []);
        return;
      }
      setState(() => _searching = true);
      final geo = ref.read(geocodingServiceProvider);
      final results = await geo.search(q);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    });
  }

  Future<void> _pickDestination(GeoSearchResult r) async {
    FocusScope.of(context).unfocus();
    _searchCtrl.clear();
    setState(() => _results = []);
    ref.read(mapControllerProvider.notifier).setDestination(
        GeoLatLng(
            latitude: r.location.latitude, longitude: r.location.longitude),
        label: r.name);
    await _route();
  }

  Future<void> _onMapLongPress(double lat, double lon) async {
    FocusScope.of(context).unfocus();
    _searchCtrl.clear();
    setState(() => _results = []);
    final point = GeoLatLng(latitude: lat, longitude: lon);
    final mapState = ref.read(mapControllerProvider);

    if (mapState.destination != null) {
      // Already has destination -> add as intermediate waypoint
      ref.read(mapControllerProvider.notifier).addWaypoint(point);
    } else {
      ref.read(mapControllerProvider.notifier).setDestinationFromTap(lat, lon);
    }
    await _route();
  }

  Future<void> _loadNearbyCharging() async {
    final origin = ref.read(mapControllerProvider).origin ??
        const GeoLatLng(latitude: 52.5200, longitude: 13.4050);
    setState(() {
      _loadingPois = true;
      _showChargingStations = true;
    });
    final svc = ref.read(chargingStationServiceProvider);
    final pois = await svc.findNearbyCharging(center: origin);
    if (!mounted) return;
    setState(() {
      _chargingStations = pois;
      _loadingPois = false;
    });
  }

  Future<void> _route() async {
    final state = ref.read(mapControllerProvider);
    var dest = state.destination;
    if (dest == null) return;
    final origin =
        state.origin ?? const GeoLatLng(latitude: 52.5200, longitude: 13.4050);

    final waypoints = List<GeoLatLng>.from(state.waypoints);
    if (state.isRoundTrip) {
      // In round-trip mode, intermediate destination becomes a waypoint, and final destination is origin
      waypoints.add(dest);
      dest = origin;
    }

    final controllerState = ref.read(effectiveControllerProvider);
    final bmsState = ref.read(effectiveBmsProvider);
    final learnedModel = ref.read(learnedEnergyModelProvider);

    final double effectiveSoc = state.planningStartSocOverride ??
        (bmsState?.socPercent?.toDouble() ??
            (controllerState.battCapPercent > 0
                ? controllerState.battCapPercent.toDouble()
                : _customStartSoc));

    setState(() => _routing = true);
    final svc = ref.read(multiRoutingServiceProvider);
    final chargingSvc = ref.read(chargingStationServiceProvider);
    try {
      final alternatives = await svc.fetchAlternatives(
        origin: origin,
        destination: dest,
        waypoints: waypoints,
        batteryCapacityWh: learnedModel.learnedCapacityWh,
        socPercent: effectiveSoc,
        avgWhPerKm: learnedModel.baseWhPerKm,
        autoInsertChargingStops: state.autoChargingStopsEnabled,
        chargingStationService: chargingSvc,
      );
      if (!mounted) return;
      ref.read(mapControllerProvider.notifier).setAlternatives(alternatives);
      if (alternatives.isNotEmpty && mounted) {
        ref
            .read(mapControllerProvider.notifier)
            .selectAlternative(alternatives.first);
        await _showAlternativesSheet(alternatives);
      }
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  Future<void> _showAlternativesSheet(List<RouteAlternative> alts) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D1117),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('ROUTENOPTIONEN & AKKUVERBRAUCH',
                      style: TextStyle(
                          color: Colors.white.withOpacity(.7),
                          fontSize: 11,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: Colors.white54, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            for (final a in alts) ...[
              ListTile(
                leading: Icon(
                  switch (a.profile) {
                    RoutingProfile.fastestCar => Icons.speed,
                    RoutingProfile.trailForest => Icons.forest,
                    RoutingProfile.scenicTrekking => Icons.landscape,
                    RoutingProfile.ebikeOptimized => Icons.electric_bike,
                  },
                  color: const Color(0xFF00E5FF),
                ),
                title: Row(
                  children: [
                    Text(a.label,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                    if (a.profile == RoutingProfile.fastestCar) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF54E39E).withOpacity(.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('SCHNELLSTE',
                            style: TextStyle(
                                color: Color(0xFF54E39E),
                                fontSize: 9,
                                fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(
                      '${a.distanceText} · ${a.durationText}'
                      '${a.elevationText.isEmpty ? '' : ' · ${a.elevationText}'}'
                      ' · ${a.provider}',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    if (a.socEstimationText.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.battery_charging_full,
                              color: Color(0xFF54E39E), size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'Ankunft: ${a.socEstimationText}',
                            style: const TextStyle(
                                color: Color(0xFF54E39E),
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                trailing:
                    const Icon(Icons.chevron_right, color: Colors.white24),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(mapControllerProvider.notifier).selectAlternative(a);
                },
              ),
              if (a.route.elevationGainMetersTotal > 0)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: RouteElevationChart(route: a.route),
                ),
              const Divider(color: Colors.white10),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showAddFavoriteDialog(GeoLatLng location, String defaultTitle) {
    final titleCtrl = TextEditingController(text: defaultTitle);
    FavoriteType selectedType = FavoriteType.custom;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF0D1117),
          title: const Text('Favorit speichern',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Name des Ortes',
                  labelStyle: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  ChoiceChip(
                    label: const Text('Zuhause'),
                    selected: selectedType == FavoriteType.home,
                    onSelected: (s) =>
                        setDlgState(() => selectedType = FavoriteType.home),
                  ),
                  ChoiceChip(
                    label: const Text('Arbeit'),
                    selected: selectedType == FavoriteType.work,
                    onSelected: (s) =>
                        setDlgState(() => selectedType = FavoriteType.work),
                  ),
                  ChoiceChip(
                    label: const Text('Ziel'),
                    selected: selectedType == FavoriteType.custom,
                    onSelected: (s) =>
                        setDlgState(() => selectedType = FavoriteType.custom),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Abbrechen',
                  style: TextStyle(color: Colors.white54)),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
              ),
              child: const Text('Speichern',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                final fav = MapFavorite(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  title: titleCtrl.text.trim().isEmpty
                      ? defaultTitle
                      : titleCtrl.text.trim(),
                  location: location,
                  type: selectedType,
                  createdAt: DateTime.now(),
                );
                ref.read(mapControllerProvider.notifier).addFavorite(fav);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapControllerProvider);
    final controllerState = ref.watch(effectiveControllerProvider);
    final bmsState = ref.watch(effectiveBmsProvider);
    final learnedModel = ref.watch(learnedEnergyModelProvider);
    // Live Telemetry for HUD & Range
    final double currentSoc = mapState.planningStartSocOverride ??
        (bmsState?.socPercent?.toDouble() ??
            (controllerState.battCapPercent > 0
                ? controllerState.battCapPercent.toDouble()
                : _customStartSoc));

    final double effectiveSoc = currentSoc > 0 ? currentSoc : 85.0;

    final double ecoRangeKm =
        (learnedModel.learnedCapacityWh * (effectiveSoc / 100.0)) /
            (learnedModel.baseWhPerKm * 0.85);
    final double normalRangeKm =
        (learnedModel.learnedCapacityWh * (effectiveSoc / 100.0)) /
            learnedModel.baseWhPerKm;
    final double sportRangeKm =
        (learnedModel.learnedCapacityWh * (effectiveSoc / 100.0)) /
            (learnedModel.baseWhPerKm * 1.35);

    // Auto-center map on first GPS fix
    if (!_hasInitialCentered && mapState.origin != null) {
      _hasInitialCentered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(
          ll.LatLng(mapState.origin!.latitude, mapState.origin!.longitude),
          mapState.userZoom,
        );
      });
    }

    // Auto-follow navigation camera update with custom zoom
    if (mapState.isNavigating &&
        mapState.autoFollowUser &&
        mapState.origin != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(
          ll.LatLng(mapState.origin!.latitude, mapState.origin!.longitude),
          mapState.userZoom,
        );
      });
    }

    final effectiveOrigin = mapState.origin ??
        const GeoLatLng(latitude: 52.5200, longitude: 13.4050);

    final center = mapState.destination != null
        ? ll.LatLng(
            mapState.destination!.latitude, mapState.destination!.longitude)
        : ll.LatLng(effectiveOrigin.latitude, effectiveOrigin.longitude);
    final selected = mapState.selected;
    final isNavigating = mapState.isNavigating;
    final currentManeuver = (selected != null &&
            selected.route.maneuvers.isNotEmpty &&
            mapState.currentManeuverIndex < selected.route.maneuvers.length)
        ? selected.route.maneuvers[mapState.currentManeuverIndex]
        : null;

    final isHeadUp = mapState.perspective == MapPerspective.headUp;

    return LayoutBuilder(builder: (context, constraints) {
      final isLandscape = constraints.maxWidth >= 700;

      return Scaffold(
        backgroundColor: const Color(0xFF050608),
        appBar: isLandscape
            ? null // Hide full AppBar in landscape to maximize map viewport
            : AppBar(
                backgroundColor: const Color(0xFF0D1117),
                foregroundColor: Colors.white,
                title: Text(
                  isNavigating ? 'Navigation aktiv' : 'Navigation',
                  style: const TextStyle(fontSize: 16, letterSpacing: 1),
                ),
                actions: [
                  // Waypoints / Roundtrip toggle
                  IconButton(
                    icon: Icon(
                      Icons.add_location_alt_outlined,
                      color:
                          mapState.waypoints.isNotEmpty || mapState.isRoundTrip
                              ? const Color(0xFF00E5FF)
                              : Colors.white54,
                    ),
                    tooltip: 'Wegpunkte & Rundtour',
                    onPressed: () => setState(
                        () => _showWaypointsPanel = !_showWaypointsPanel),
                  ),
                  // Tour Planner toggle (Start-SOC)
                  IconButton(
                    icon: Icon(
                      Icons.tune,
                      color: _showTourPlanner
                          ? const Color(0xFF00E5FF)
                          : Colors.white54,
                    ),
                    tooltip: 'Tour-Planer (Start-SOC)',
                    onPressed: () =>
                        setState(() => _showTourPlanner = !_showTourPlanner),
                  ),
                  // Head-Up / 3D Perspective Toggle
                  IconButton(
                    icon: Icon(
                      isHeadUp ? Icons.explore : Icons.north,
                      color:
                          isHeadUp ? const Color(0xFF00E5FF) : Colors.white54,
                    ),
                    tooltip: isHeadUp
                        ? 'Fahrtrichtung oben (3D)'
                        : 'Nordausrichtung',
                    onPressed: () => ref
                        .read(mapControllerProvider.notifier)
                        .togglePerspective(),
                  ),
                  // Charging stations toggle
                  IconButton(
                    icon: Icon(
                      Icons.ev_station,
                      color: _showChargingStations
                          ? const Color(0xFF54E39E)
                          : Colors.white54,
                    ),
                    tooltip: 'Ladesäulen & Steckdosen anzeigen',
                    onPressed: () {
                      if (!_showChargingStations) {
                        _loadNearbyCharging();
                      } else {
                        setState(() => _showChargingStations = false);
                      }
                    },
                  ),
                  // Satellite View Toggle
                  IconButton(
                    icon: Icon(
                      _isSatellite
                          ? Icons.map_outlined
                          : Icons.satellite_alt_outlined,
                      color: Colors.white70,
                    ),
                    tooltip:
                        _isSatellite ? 'Standardkarte' : 'Satellitenansicht',
                    onPressed: () =>
                        setState(() => _isSatellite = !_isSatellite),
                  ),
                ],
              ),
        body: Stack(children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: mapState.userZoom,
              initialRotation: isHeadUp ? mapState.currentHeadingDeg : 0.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture) {
                  ref
                      .read(mapControllerProvider.notifier)
                      .setUserZoom(pos.zoom);
                }
              },
              onLongPress: (_, pos) =>
                  _onMapLongPress(pos.latitude, pos.longitude),
            ),
            children: [
              TileLayer(
                urlTemplate: _isSatellite
                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'de.neuleo.arcdash',
                maxNativeZoom: 19,
              ),

              // 3-Zone Dynamic Range Heatmap Circles (High contrast on both light vector and dark satellite maps)
              if (effectiveOrigin != null)
                CircleLayer(circles: [
                  // Eco Zone (Max Reach) - Green
                  CircleMarker(
                    point: ll.LatLng(
                        effectiveOrigin.latitude, effectiveOrigin.longitude),
                    radius: ecoRangeKm * 1000,
                    useRadiusInMeter: true,
                    color: const Color(0xFF00C853).withOpacity(0.12),
                    borderColor: const Color(0xFF00C853),
                    borderStrokeWidth: 2.5,
                  ),
                  // Normal Zone - Vibrant Cyan/Blue
                  CircleMarker(
                    point: ll.LatLng(
                        effectiveOrigin.latitude, effectiveOrigin.longitude),
                    radius: normalRangeKm * 1000,
                    useRadiusInMeter: true,
                    color: const Color(0xFF0091EA).withOpacity(0.15),
                    borderColor: const Color(0xFF0091EA),
                    borderStrokeWidth: 3.0,
                  ),
                  // Sport / Heavy Terrain Zone - Orange/Red
                  CircleMarker(
                    point: ll.LatLng(
                        effectiveOrigin.latitude, effectiveOrigin.longitude),
                    radius: sportRangeKm * 1000,
                    useRadiusInMeter: true,
                    color: const Color(0xFFFF6D00).withOpacity(0.15),
                    borderColor: const Color(0xFFFF6D00),
                    borderStrokeWidth: 2.5,
                  ),
                ]),

              // Charging Station POI Markers
              if (_showChargingStations && _chargingStations.isNotEmpty)
                MarkerLayer(
                  markers: _chargingStations.map((poi) {
                    return Marker(
                      width: 36,
                      height: 36,
                      point: ll.LatLng(
                          poi.location.latitude, poi.location.longitude),
                      child: GestureDetector(
                        onTap: () {
                          ref
                              .read(mapControllerProvider.notifier)
                              .setDestination(
                                poi.location,
                                label: poi.name,
                              );
                          _route();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: poi.hasSchuko
                                ? const Color(0xFF54E39E)
                                : const Color(0xFF00E5FF),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.5),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                          child: const Icon(Icons.ev_station,
                              color: Colors.black, size: 20),
                        ),
                      ),
                    );
                  }).toList(growable: false),
                ),

              // User location, Intermediate Waypoints, and Destination Markers
              if (mapState.destination != null ||
                  mapState.origin != null ||
                  mapState.waypoints.isNotEmpty)
                MarkerLayer(markers: [
                  // Destination marker
                  if (mapState.destination != null)
                    Marker(
                      width: 44,
                      height: 44,
                      point: ll.LatLng(mapState.destination!.latitude,
                          mapState.destination!.longitude),
                      child: GestureDetector(
                        onTap: () => _showAddFavoriteDialog(
                            mapState.destination!,
                            mapState.destinationLabel ?? 'Gespeicherter Ort'),
                        child: const Icon(Icons.location_on,
                            color: Color(0xFFFF5252), size: 40),
                      ),
                    ),

                  // Intermediate Waypoints Markers
                  for (int i = 0; i < mapState.waypoints.length; i++)
                    Marker(
                      width: 32,
                      height: 32,
                      point: ll.LatLng(mapState.waypoints[i].latitude,
                          mapState.waypoints[i].longitude),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB300),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 13),
                          ),
                        ),
                      ),
                    ),

                  // User location marker
                  if (mapState.origin != null)
                    Marker(
                      width: 28,
                      height: 28,
                      point: ll.LatLng(mapState.origin!.latitude,
                          mapState.origin!.longitude),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF2979FF).withOpacity(0.3),
                            ),
                          ),
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF2979FF),
                              border:
                                  Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ]),

              // Route Polyline
              if (selected != null && selected.route.geometry.isNotEmpty)
                PolylineLayer(polylines: [
                  Polyline(
                    points: selected.route.geometry
                        .map((g) => ll.LatLng(g.latitude, g.longitude))
                        .toList(growable: false),
                    strokeWidth: isNavigating ? 6 : 5,
                    color: const Color(0xFF00E5FF),
                  ),
                ]),
            ],
          ),

          // Floating Landscape Top Action Bar (Compact)
          if (isLandscape && !isNavigating)
            Positioned(
              top: 14,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xCC0D1117),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.add_location_alt_outlined,
                        color: mapState.waypoints.isNotEmpty ||
                                mapState.isRoundTrip
                            ? const Color(0xFF00E5FF)
                            : Colors.white70,
                      ),
                      tooltip: 'Wegpunkte & Rundtour',
                      onPressed: () => setState(
                          () => _showWaypointsPanel = !_showWaypointsPanel),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.tune,
                        color: _showTourPlanner
                            ? const Color(0xFF00E5FF)
                            : Colors.white70,
                      ),
                      tooltip: 'Tour-Planer',
                      onPressed: () =>
                          setState(() => _showTourPlanner = !_showTourPlanner),
                    ),
                    IconButton(
                      icon: Icon(
                        isHeadUp ? Icons.explore : Icons.north,
                        color:
                            isHeadUp ? const Color(0xFF00E5FF) : Colors.white70,
                      ),
                      tooltip: isHeadUp ? 'Head-Up' : 'Nord',
                      onPressed: () => ref
                          .read(mapControllerProvider.notifier)
                          .togglePerspective(),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.ev_station,
                        color: _showChargingStations
                            ? const Color(0xFF54E39E)
                            : Colors.white70,
                      ),
                      tooltip: 'Ladesäulen',
                      onPressed: () {
                        if (!_showChargingStations) {
                          _loadNearbyCharging();
                        } else {
                          setState(() => _showChargingStations = false);
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        _isSatellite
                            ? Icons.map_outlined
                            : Icons.satellite_alt_outlined,
                        color: Colors.white70,
                      ),
                      tooltip: 'Satellit',
                      onPressed: () =>
                          setState(() => _isSatellite = !_isSatellite),
                    ),
                  ],
                ),
              ),
            ),

          // Live E-Moto HUD Cockpit Overlay on Map (Top-Left under search in portrait, bottom-left in landscape)
          Positioned(
            top: isNavigating
                ? (isLandscape ? null : 90)
                : (isLandscape ? null : 120),
            bottom: isLandscape ? (selected != null ? 140 : 20) : null,
            left: isLandscape ? 20 : 14,
            child: MapCockpitHud(
              speedKph: controllerState.speedKph,
              socPercent: currentSoc.round(),
              powerKw: controllerState.powerKw,
              motorTempC: controllerState.motorTempC,
            ),
          ),

          // Waypoints & Roundtrip Planning Panel
          if (_showWaypointsPanel && !isNavigating)
            Positioned(
              top: isLandscape ? 70 : 70,
              left: isLandscape ? 70 : 12,
              right: isLandscape ? null : 12,
              width: isLandscape ? 380 : null,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xF50D1117),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFF00E5FF).withOpacity(0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'WEGPUNKTE & RUNDTOUR',
                          style: TextStyle(
                              color: Color(0xFF00E5FF),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 1),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white54, size: 18),
                          onPressed: () =>
                              setState(() => _showWaypointsPanel = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Roundtrip toggle button
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.replay,
                        color: mapState.isRoundTrip
                            ? const Color(0xFF54E39E)
                            : Colors.white54,
                      ),
                      title: const Text('Zurück zum Start (Rundtour)',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                      trailing: Switch(
                        value: mapState.isRoundTrip,
                        activeColor: const Color(0xFF54E39E),
                        onChanged: (_) {
                          ref
                              .read(mapControllerProvider.notifier)
                              .toggleRoundTrip();
                          _route();
                        },
                      ),
                    ),
                    // Auto-Charging Stops toggle
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.ev_station,
                        color: mapState.autoChargingStopsEnabled
                            ? const Color(0xFF00E5FF)
                            : Colors.white54,
                      ),
                      title: const Text('Auto-Ladestopps bei leerem Akku',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                      subtitle: const Text(
                          'Fügt automatisch Ladesäulen auf halber Strecke ein',
                          style:
                              TextStyle(color: Colors.white38, fontSize: 10)),
                      trailing: Switch(
                        value: mapState.autoChargingStopsEnabled,
                        activeColor: const Color(0xFF00E5FF),
                        onChanged: (_) {
                          ref
                              .read(mapControllerProvider.notifier)
                              .toggleAutoChargingStops();
                          _route();
                        },
                      ),
                    ),
                    // Point of No Return warning toggle
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.warning_amber_rounded,
                        color: mapState.pointOfNoReturnEnabled
                            ? Colors.orangeAccent
                            : Colors.white54,
                      ),
                      title: const Text('Point of No Return Warnung',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                      subtitle: const Text(
                          'Warnt, sobald Akku nur noch für den Heimweg reicht',
                          style:
                              TextStyle(color: Colors.white38, fontSize: 10)),
                      trailing: Switch(
                        value: mapState.pointOfNoReturnEnabled,
                        activeColor: Colors.orangeAccent,
                        onChanged: (_) {
                          ref
                              .read(mapControllerProvider.notifier)
                              .togglePointOfNoReturn();
                        },
                      ),
                    ),
                    if (mapState.waypoints.isNotEmpty) ...[
                      const Divider(color: Colors.white12),
                      for (int i = 0; i < mapState.waypoints.length; i++)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 10,
                            backgroundColor: const Color(0xFFFFB300),
                            child: Text('${i + 1}',
                                style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ),
                          title: Text(
                              'Stopp ${i + 1} (${mapState.waypoints[i].latitude.toStringAsFixed(3)}, ${mapState.waypoints[i].longitude.toStringAsFixed(3)})',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.redAccent, size: 18),
                            onPressed: () {
                              ref
                                  .read(mapControllerProvider.notifier)
                                  .removeWaypoint(i);
                              _route();
                            },
                          ),
                        ),
                    ],
                    const SizedBox(height: 4),
                    const Text(
                      'Tipp: Halte lange auf die Karte gedrückt, um weitere Zwischenstopps hinzuzufügen.',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),

          // Tour Planner (Start-SOC Slider) Card Overlay
          if (_showTourPlanner && !isNavigating)
            Positioned(
              top: isLandscape ? 70 : 70,
              left: isLandscape ? 70 : 12,
              right: isLandscape ? null : 12,
              width: isLandscape ? 380 : null,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xF20D1117),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFF00E5FF).withOpacity(0.4)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOUR-PLANER: START-AKKU',
                          style: TextStyle(
                              color: Color(0xFF00E5FF),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              letterSpacing: 1),
                        ),
                        Text(
                          '${currentSoc.round()} %',
                          style: const TextStyle(
                              color: Color(0xFF54E39E),
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                        ),
                      ],
                    ),
                    Slider(
                      value: currentSoc,
                      min: 5.0,
                      max: 100.0,
                      divisions: 19,
                      activeColor: const Color(0xFF00E5FF),
                      onChanged: (v) {
                        setState(() => _customStartSoc = v);
                        ref
                            .read(mapControllerProvider.notifier)
                            .setPlanningStartSoc(v);
                      },
                    ),
                  ],
                ),
              ),
            ),

          // Search bar & Favorites Quick Row (hidden during navigation)
          if (!isNavigating)
            Positioned(
              top: 10,
              left: isLandscape ? 70 : 12,
              right: isLandscape ? 300 : 12,
              child: Column(children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Ziel suchen (oder Karte gedrückt halten)…',
                    hintStyle:
                        const TextStyle(color: Colors.white38, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)))
                        : (_searchCtrl.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear,
                                    color: Colors.white38),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _results = []);
                                })),
                    filled: true,
                    fillColor: const Color(0xE6111518),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                  ),
                ),

                // Favorites Quick Filter Chips (Home, Work, Recents)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // Quick Action Buttons
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            backgroundColor: const Color(0xF00D1117),
                            avatar: const Icon(Icons.add_location_alt_outlined,
                                color: Color(0xFF00E5FF), size: 16),
                            label: const Text('+ Wegpunkt',
                                style: TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                            onPressed: () => setState(() =>
                                _showWaypointsPanel = !_showWaypointsPanel),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            backgroundColor: const Color(0xF00D1117),
                            avatar: const Icon(Icons.star_border,
                                color: Color(0xFFFFB300), size: 16),
                            label: const Text('+ Favorit',
                                style: TextStyle(
                                    color: Color(0xFFFFB300),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                            onPressed: () {
                              final currentCenter =
                                  _mapController.camera.center;
                              _showAddFavoriteDialog(
                                GeoLatLng(
                                  latitude: currentCenter.latitude,
                                  longitude: currentCenter.longitude,
                                ),
                                'Mein Ort',
                              );
                            },
                          ),
                        ),
                        for (final fav in mapState.favorites)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              backgroundColor: const Color(0xE6111518),
                              avatar: Icon(
                                fav.type == FavoriteType.home
                                    ? Icons.home
                                    : (fav.type == FavoriteType.work
                                        ? Icons.work
                                        : Icons.star),
                                color: const Color(0xFF00E5FF),
                                size: 16,
                              ),
                              label: Text(fav.title,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12)),
                              onPressed: () {
                                ref
                                    .read(mapControllerProvider.notifier)
                                    .setDestination(
                                      fav.location,
                                      label: fav.title,
                                    );
                                _route();
                              },
                            ),
                          ),
                        for (final rec in mapState.recents.take(3))
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              backgroundColor: const Color(0xCC111518),
                              avatar: const Icon(Icons.history,
                                  color: Colors.white38, size: 16),
                              label: Text(rec.title,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                              onPressed: () {
                                ref
                                    .read(mapControllerProvider.notifier)
                                    .setDestination(
                                      rec.location,
                                      label: rec.title,
                                    );
                                _route();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 260),
                    decoration: BoxDecoration(
                      color: const Color(0xF2111518),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final r = _results[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place,
                              color: Color(0xFF00E5FF), size: 22),
                          title: Text(r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14)),
                          subtitle: r.detail.isEmpty
                              ? null
                              : Text(r.detail,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 11)),
                          onTap: () => _pickDestination(r),
                        );
                      },
                    ),
                  ),
                ],
              ]),
            ),

          // Turn-by-Turn Guidance Banner at top when Navigating
          if (isNavigating && currentManeuver != null)
            Positioned(
              top: 10,
              left: isLandscape ? 70 : 12,
              right: isLandscape ? 70 : 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xF50D1117),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: const Color(0xFF00E5FF), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      switch (currentManeuver.modifier) {
                        'left' || 'sharp left' => Icons.turn_left,
                        'right' || 'sharp right' => Icons.turn_right,
                        'slight left' => Icons.turn_slight_left,
                        'slight right' => Icons.turn_slight_right,
                        _ => Icons.straight,
                      },
                      color: const Color(0xFF00E5FF),
                      size: 36,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            currentManeuver.instruction,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold),
                          ),
                          if (currentManeuver.distanceMeters > 0)
                            Text(
                              'in ${(currentManeuver.distanceMeters >= 1000 ? "${(currentManeuver.distanceMeters / 1000).toStringAsFixed(1)} km" : "${currentManeuver.distanceMeters.round()} m")}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward,
                          color: Colors.white54),
                      tooltip: 'Nächster Schritt',
                      onPressed: () => ref
                          .read(mapControllerProvider.notifier)
                          .nextManeuver(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                      tooltip: 'Navigation beenden',
                      onPressed: () => ref
                          .read(mapControllerProvider.notifier)
                          .stopNavigation(),
                    ),
                  ],
                ),
              ),
            ),

          // Point of No Return Alert Banner
          if (mapState.pointOfNoReturnTriggered &&
              mapState.pointOfNoReturnEnabled)
            Positioned(
              top: isNavigating ? 90 : (isLandscape ? 60 : 70),
              left: isLandscape ? 70 : 12,
              right: isLandscape ? 70 : 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xF5331505),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orangeAccent, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.orangeAccent, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'POINT OF NO RETURN ERREICHT',
                            style: TextStyle(
                                color: Colors.orangeAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 1),
                          ),
                          Text(
                            'Rest-Akku (${currentSoc.round()} %) reicht nur noch für den Heimweg (~${mapState.neededReturnSocPercent.round()} % nötig). Jetzt umkehren oder Zwischenladung einplanen!',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // My Location Button (Bottom-Right)
          Positioned(
            right: 16,
            bottom: isLandscape
                ? 20
                : (selected != null ? (isNavigating ? 100 : 150) : 20),
            child: FloatingActionButton.small(
              heroTag: 'my_location_btn',
              backgroundColor: const Color(0xF2111518),
              foregroundColor: const Color(0xFF2979FF),
              tooltip: 'Zu meinem Standort',
              onPressed: () async {
                await ref
                    .read(mapControllerProvider.notifier)
                    .useCurrentLocationAsOrigin();
                final pos = ref.read(mapControllerProvider).origin;
                if (pos != null) {
                  _mapController.move(
                    ll.LatLng(pos.latitude, pos.longitude),
                    ref.read(mapControllerProvider).userZoom,
                  );
                }
              },
              child: const Icon(Icons.my_location),
            ),
          ),

          // Route Summary & Action Card (Landscape: Compact Floating Card on Bottom-Left; Portrait: Bottom Bar)
          if (selected != null)
            Positioned(
              bottom: 14,
              left: 12,
              right: isLandscape ? null : 12,
              width: isLandscape ? 400 : null,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xF5111518),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFF00E5FF).withOpacity(.4), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('${selected.label} · ${selected.provider}',
                                    style: const TextStyle(
                                        color: Color(0xFF00E5FF),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13)),
                                if (selected.socEstimationText.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF54E39E)
                                          .withOpacity(.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      selected.socEstimationText,
                                      style: const TextStyle(
                                          color: Color(0xFF54E39E),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${selected.distanceText} · ${selected.durationText}'
                              '${selected.elevationText.isEmpty ? "" : " · ${selected.elevationText}"}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon:
                            const Icon(Icons.alt_route, color: Colors.white70),
                        tooltip: 'Alternative Routen & Höhenprofil',
                        onPressed: () =>
                            _showAlternativesSheet(mapState.alternatives),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isNavigating
                                  ? Colors.redAccent.withOpacity(0.8)
                                  : const Color(0xFF00E5FF),
                              foregroundColor:
                                  isNavigating ? Colors.white : Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: Icon(
                                isNavigating ? Icons.stop : Icons.navigation),
                            label: Text(
                              isNavigating
                                  ? 'NAVIGATION BEENDEN'
                                  : 'NAVIGATION STARTEN',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                  fontSize: 13),
                            ),
                            onPressed: () {
                              if (isNavigating) {
                                ref
                                    .read(mapControllerProvider.notifier)
                                    .stopNavigation();
                              } else {
                                ref
                                    .read(mapControllerProvider.notifier)
                                    .startNavigation();
                                if (mapState.origin != null) {
                                  _mapController.move(
                                    ll.LatLng(mapState.origin!.latitude,
                                        mapState.origin!.longitude),
                                    16.0,
                                  );
                                }
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white10,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.clear, color: Colors.white54),
                          tooltip: 'Route löschen',
                          onPressed: () {
                            ref
                                .read(mapControllerProvider.notifier)
                                .clearRoute();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Routing progress overlay
          if (_routing || _loadingPois)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black38,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        _loadingPois
                            ? 'Suche Ladesäulen in der Nähe…'
                            : 'Berechne Routen & Akkubedarf…',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ]),
      );
    });
  }
}
