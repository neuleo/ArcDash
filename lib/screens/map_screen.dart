import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:arcdash/domain/navigation/navigation_interfaces.dart';
import 'package:arcdash/providers/map_provider.dart';
import 'package:arcdash/services/geocoding/geocoding_service.dart';
import 'package:arcdash/services/routing/multi_routing_service.dart';

/// Full-screen map with destination search, free multi-provider routing and
/// route alternatives. See plan/16-map-navigation.md.
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
    ref.read(mapControllerProvider.notifier).setDestination(
        GeoLatLng(
            latitude: r.location.latitude, longitude: r.location.longitude),
        label: r.name);
    setState(() => _results = []);
    await _route();
  }

  Future<void> _route() async {
    final state = ref.read(mapControllerProvider);
    final dest = state.destination;
    if (dest == null) return;
    final origin = state.origin ??
        const GeoLatLng(
            latitude: 52.5200, longitude: 13.4050); // Berlin default

    setState(() => _routing = true);
    final svc = ref.read(multiRoutingServiceProvider);
    try {
      final alternatives = await svc.fetchAlternatives(
        origin: origin,
        destination: dest,
      );
      if (!mounted) return;
      ref.read(mapControllerProvider.notifier).setAlternatives(alternatives);
      if (alternatives.isNotEmpty && mounted) {
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
              padding: const EdgeInsets.all(16),
              child: Text('ROUTE WÄHLEN',
                  style: TextStyle(
                      color: Colors.white.withOpacity(.7),
                      fontSize: 12,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold)),
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
                title: Text(a.label,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${a.distanceText} · ${a.durationText}'
                  '${a.elevationText.isEmpty ? '' : ' · ${a.elevationText}'}'
                  ' · ${a.provider}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: a.profile == RoutingProfile.fastestCar
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF54E39E).withOpacity(.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('SCHNELLSTE',
                            style: TextStyle(
                                color: const Color(0xFF54E39E),
                                fontSize: 9,
                                fontWeight: FontWeight.w900)),
                      )
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  ref.read(mapControllerProvider.notifier).selectAlternative(a);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapControllerProvider);
    final center = mapState.destination != null
        ? ll.LatLng(
            mapState.destination!.latitude, mapState.destination!.longitude)
        : (mapState.origin != null
            ? ll.LatLng(mapState.origin!.latitude, mapState.origin!.longitude)
            : const ll.LatLng(52.5200, 13.4050));
    final selected = mapState.selected;

    return Scaffold(
      backgroundColor: const Color(0xFF050608),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        title: const Text('Navigation',
            style: TextStyle(fontSize: 16, letterSpacing: 1)),
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
            onLongPress: (_, pos) => ref
                .read(mapControllerProvider.notifier)
                .setDestinationFromTap(pos.latitude, pos.longitude),
          ),
          children: [
            TileLayer(
              urlTemplate: _isSatellite
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'de.neuleo.arcdash',
              maxNativeZoom: 19,
            ),
            if (mapState.destination != null)
              MarkerLayer(markers: [
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
                    width: 36,
                    height: 36,
                    point: ll.LatLng(
                        mapState.origin!.latitude, mapState.origin!.longitude),
                    child: const Icon(Icons.my_location,
                        color: Color(0xFF54E39E), size: 32),
                  ),
              ]),
            if (selected != null && selected.route.geometry.isNotEmpty)
              PolylineLayer(polylines: [
                Polyline(
                  points: selected.route.geometry
                      .map((g) => ll.LatLng(g.latitude, g.longitude))
                      .toList(growable: false),
                  strokeWidth: 5,
                  color: const Color(0xFF00E5FF),
                ),
              ]),
          ],
        ),

        // Search bar + results
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
                hintText: 'Ziel suchen…',
                hintStyle: const TextStyle(color: Colors.white38),
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
                            icon:
                                const Icon(Icons.clear, color: Colors.white38),
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
                          color: const Color(0xFF00E5FF), size: 22),
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

        // My Location Button (Bottom-Left above possible route card)
        Positioned(
          left: 16,
          bottom: selected != null ? 90 : 20,
          child: FloatingActionButton.small(
            heroTag: 'my_location_btn',
            backgroundColor: const Color(0xF2111518),
            foregroundColor: const Color(0xFF54E39E),
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

        // Route summary card when a route is selected
        if (selected != null)
          Positioned(
            bottom: 14,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xF2111518),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: const Color(0xFF00E5FF).withOpacity(.4)),
              ),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('${selected.label} · ${selected.provider}',
                          style: TextStyle(
                              color: const Color(0xFF00E5FF),
                              fontWeight: FontWeight.w800,
                              fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        '${selected.distanceText} · ${selected.durationText}'
                        '${selected.elevationText.isEmpty ? "" : " · ${selected.elevationText}"}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                    ])),
                IconButton(
                  icon: const Icon(Icons.alt_route, color: Colors.white54),
                  tooltip: 'Alternative Routen',
                  onPressed: () =>
                      _showAlternativesSheet(mapState.alternatives),
                ),
              ]),
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
