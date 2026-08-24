# ArcDash Projekt-Wissen (persistente Notizen)

## Map/Navigation (v2.7.x, 2026-08-24 live getestet)

Multi-Provider-Routing, alle kostenlos ohne API-Key:
- **OSRM** `routing.openstreetmap.de/routed-car` — schnellste Route, GeoJSON-Geometry
- **BRouter** `brouter.de/brouter` — `profile=mtb` (Wald/Trail), `profile=trekking` (Scenic).
  **ACHTUNG: `total-time` ist in SEKUNDEN** (nicht Minuten!) — verursachte mal "198h"-Bug
- **Valhalla** `valhalla1.openstreetmap.de/route` — bicycle Mountain, deutsche Manövertexte.
  **Encoded Polyline precision 5** (nicht 6 wie Google!)
- **Photon** `photon.komoot.io/api/` — Geocoding, Nominatim-Fallback
- flutter_map ^8.1 + latlong2; OSM-Tiles brauchen User-Agent-Package-Name
- Fixtures echter API-Antworten: `test/fixtures/` (osrm_route.json, brouter_mtb.geojson, brouter_trekking.geojson)

## redroid End-to-End Setup

- Android 11 @ `172.24.1.20:5555` (docker-vm KVM 172.24.1.20, binderfs nötig;
  unprivilegierter LXC crasht Android-init mit Signal 129)
- MCP mobile-mcp: konfiguriert in `/home/leon/.hermes/profiles/coder/config.yaml`
  **auf dem LXC-Host** (Gateway PID 4427, user leon) — NICHT im SSH-Container `/root/.hermes/`!
  Reload via `/reload_mcp`
- App: `com.arcdash.arcdash/.MainActivity`
- Nav-Tabs (portrait, y=1710): Cockpit x134, Tuning x406, Fahrten x675, Navigation x756, Settings x947
- Dev Tools: Settings → „Dev Tools & KI-Kontext" (540,665) → Demo-Switch (955,500)
- Demo-Modus: 6 Szenarien, Cockpit liest effectiveControllerProvider (v2.6.1+),
  telemetrySamples müssen befüllt sein sonst „Fehlt" (v2.6.3-Fix)

## Kritische Android-Fallen

- **INTERNET-Permission war NICHT im Manifest** → flaky HTTP in Release-Builds
  (OSRM ging, Valhalla/BRouter teils nicht). Fixed in v2.7.2 (Commit 186ed47).
  Bei neuen Netzwerk-Features immer Manifest checken!
- Docker im LXC braucht `security_opt: apparmor=unconfined` (docker-compose.yml gepatcht)
- Release-Verify: immer GitHub-API auf exakten Tag prüfen, `releases/latest` kann laggen
