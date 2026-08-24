import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:arcdash/domain/navigation/navigation_interfaces.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/demo_controller_provider.dart';
import 'package:arcdash/providers/demo_mode_provider.dart';
import 'package:arcdash/providers/map_provider.dart';
import 'package:arcdash/services/geocoding/geocoding_service.dart';
import 'package:arcdash/services/routing/multi_routing_service.dart';

/// Full-screen map with destination search, free multi-provider routing,
/// turn-by-turn guidance, range circle and live battery SOC forecast.
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
  bool _searching = false;
  bool _routing = false;
  bool _isSatellite = false;
  bool _hasInitialCentered = false;

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
    ref.read(mapControllerProvider.notifier).setDestinationFromTap(lat, lon);
    await _route();
  }

  Future<void> _route() async {
    final state = ref.read(mapControllerProvider);
    final dest = state.destination;
    if (dest == null) return;
    final origin = state.origin ??
        const GeoLatLng(
            latitude: 52.5200, longitude: 13.4050); // Berlin default

    final controllerState = ref.read(effectiveControllerProvider);
    final bmsState = ref.read(effectiveBmsProvider);
    final learnedProfile = ref.read(rangePredictionStateProvider);

    final double socPercent = bmsState?.socPercent?.toDouble() ??
        (controllerState.battCapPercent > 0
            ? controllerState.battCapPercent.toDouble()
            : 85.0);

    final double batteryCapacityWh =
        learnedProfile?.learnedCapacityWh ?? 4000.0;

    final double? avgWhPerKm =
        (learnedProfile?.consumptionHistoryWhPerKm.isNotEmpty ?? false)
            ? (learnedProfile!.consumptionHistoryWhPerKm
                    .reduce((a, b) => a + b) /
                learnedProfile.consumptionHistoryWhPerKm.length)
            : 35.0;

    setState(() => _routing = true);
    final svc = ref.read(multiRoutingServiceProvider);
    try {
      final alternatives = await svc.fetchAlternatives(
        origin: origin,
        destination: dest,
        batteryCapacityWh: batteryCapacityWh,
        socPercent: socPercent,
        avgWhPerKm: avgWhPerKm,
      );
      if (!mounted) return;
      ref.read(mapControllerProvider.notifier).setAlternatives(alternatives);
      if (alternatives.isNotEmpty && mounted) {
        // Auto-select first alternative and show bottom sheet
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
      backgroundColor: const Color(0xFF0D1117),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
            for (final a in alts)
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
            const SizedBox(height: 12),
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
    final learnedProfile = ref.watch(rangePredictionStateProvider);

    // Calculate dynamic range in km from battery SOC + learned consumption
    final double currentSoc = bmsState?.socPercent?.toDouble() ??
        (controllerState.battCapPercent > 0
            ? controllerState.battCapPercent.toDouble()
            : 85.0);
    final double capacityWh = learnedProfile?.learnedCapacityWh ?? 4000.0;
    final double avgWhKm =
        (learnedProfile?.consumptionHistoryWhPerKm.isNotEmpty ?? false)
            ? (learnedProfile!.consumptionHistoryWhPerKm
                    .reduce((a, b) => a + b) /
                learnedProfile.consumptionHistoryWhPerKm.length)
            : 35.0;
    final double estimatedRangeKm =
        (capacityWh * (currentSoc / 100.0)) / avgWhKm;

    // Auto-center map to origin upon first valid GPS fix
    if (!_hasInitialCentered && mapState.origin != null) {
      _hasInitialCentered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(
          ll.LatLng(mapState.origin!.latitude, mapState.origin!.longitude),
          13.5,
        );
      });
    }

    final center = mapState.destination != null
        ? ll.LatLng(
            mapState.destination!.latitude, mapState.destination!.longitude)
        : (mapState.origin != null
            ? ll.LatLng(mapState.origin!.latitude, mapState.origin!.longitude)
            : const ll.LatLng(52.5200, 13.4050));
    final selected = mapState.selected;
    final isNavigating = mapState.isNavigating;
    final currentManeuver = (selected != null &&
            selected.route.maneuvers.isNotEmpty &&
            mapState.currentManeuverIndex < selected.route.maneuvers.length)
        ? selected.route.maneuvers[mapState.currentManeuverIndex]
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF050608),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        title: Text(
          isNavigating ? 'Navigation aktiv' : 'Navigation',
          style: const TextStyle(fontSize: 16, letterSpacing: 1),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isSatellite ? Icons.map_outlined : Icons.satellite_alt_outlined,
              color: Colors.white70,
            ),
            tooltip: _isSatellite ? 'Standardkarte' : 'Satellitenansicht',
            onPressed: () => setState(() => _isSatellite = !_isSatellite),
          ),
        ],
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom:
                selected != null || mapState.destination != null ? 13.5 : 11,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
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

            // Estimated Reichweiten-Kreis (Range circle in km around user location)
            if (mapState.origin != null && estimatedRangeKm > 1.0)
              CircleLayer(circles: [
                CircleMarker(
                  point: ll.LatLng(
                      mapState.origin!.latitude, mapState.origin!.longitude),
                  radius: estimatedRangeKm * 1000, // meters
                  useRadiusInMeter: true,
                  color: const Color(0xFF00E5FF).withOpacity(0.08),
                  borderColor: const Color(0xFF00E5FF).withOpacity(0.4),
                  borderStrokeWidth: 1.5,
                ),
              ]),

            // User location & Destination markers
            if (mapState.destination != null || mapState.origin != null)
              MarkerLayer(markers: [
                if (mapState.destination != null)
                  Marker(
                    width: 44,
                    height: 44,
                    point: ll.LatLng(mapState.destination!.latitude,
                        mapState.destination!.longitude),
                    child: const Icon(Icons.location_on,
                        color: Color(0xFFFF5252), size: 40),
                  ),
                if (mapState.origin != null)
                  Marker(
                    width: 28,
                    height: 28,
                    point: ll.LatLng(
                        mapState.origin!.latitude, mapState.origin!.longitude),
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
                            border: Border.all(color: Colors.white, width: 2.5),
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

        // Search bar + results (hidden during active turn-by-turn navigation)
        if (!isNavigating)
          Positioned(
            top: 10,
            left: 12,
            right: 12,
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
                              child: CircularProgressIndicator(strokeWidth: 2)))
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
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xF50D1117),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
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
                    icon:
                        const Icon(Icons.arrow_forward, color: Colors.white54),
                    tooltip: 'Nächster Schritt',
                    onPressed: () =>
                        ref.read(mapControllerProvider.notifier).nextManeuver(),
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

        // My Location Button (Bottom-Right)
        Positioned(
          right: 16,
          bottom: selected != null ? (isNavigating ? 100 : 150) : 20,
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
                  15.0,
                );
              }
            },
            child: const Icon(Icons.my_location),
          ),
        ),

        // Route Summary & Action Card at bottom
        if (selected != null)
          Positioned(
            bottom: 14,
            left: 12,
            right: 12,
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
                      icon: const Icon(Icons.alt_route, color: Colors.white70),
                      tooltip: 'Alternative Routen',
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
                          ref.read(mapControllerProvider.notifier).clearRoute();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        // Routing progress overlay
        if (_routing)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.black38,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ]),
    );
  }
}
