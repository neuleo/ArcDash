# 16 — Map & Navigation Feature (v2.7.0)

## Ziel

Vollwertige Navigation wie Google Maps — aber **komplett kostenlos** (keine API-Keys,
keine Limits außer Fair-Use, keine Kosten). E-Moto-tauglich: Offroad-/Wald-Routen,
Höhenmeter-Energieprognose mit dem gelernten EnergyProfile.

## Recherche-Ergebnis (alle APIs live getestet am 2026-08-23, alle OHNE API-Key)

| Dienst | Zweck | Status | Fair-Use |
|--------|-------|--------|----------|
| **OSM Standard Tiles** | Karten-Kacheln | ✅ HTTP 200, 36 KB/Kachel | Browserlike Policy, UA-Pflicht |
| **FOSSGIS OSRM** (`routing.openstreetmap.de`) | Auto-Routing + Alternativen | ✅ 2 Alternativen in ~240 ms | Community-Server |
| **BRouter** (`brouter.de`) | **Offroad/Trail/MTB/Moped-Profile**, GeoJSON, Höhenmeter im Track! | ✅ mtb/moped/trekking/car-fast getestet | Community-Server |
| **Valhalla FOSSGIS** (`valhalla1.openstreetmap.de`) | Bicycle-Mountain + deutsche Sprachausgaben | ✅ inkl. Manövertexten DE | Community-Server |
| **Photon** (`photon.komoot.io`) | Geocoding (Suche), DE-Support | ✅ | Komoot, fair use |
| **OpenTopoData / open-elevation** | Höhendaten für beliebige Punkte | ✅ SRTM 90 m | Fair use |

**Entscheidung:**
- **Karten:** flutter_map + OSM-Tiles (User-Agent `ArcDash/2.6.x` setzen — Pflicht!)
- **Routing-Multi-Provider:**
  - „Schnellste Route" → OSRM routed-car
  - „Nur Wald/Trail" → BRouter Profil `mtb` (bevorzugt tracks/paths)
  - „Gemütlich/Effizient" → BRouter `trekking`
  - „E-Bike-optimiert" → Valhalla bicycle+Mountain (nutzt Höhe fürs Costing!)
- **Geocoding:** Photon (primär), Nominatim (Fallback)
- **Höhe:** OpenTopoData Batch-API; Route-Höhen kommen schon aus BRouter-GeoJSON (`filtered ascend`)
- flutter_map latest = 8.3.1 braucht Flutter ≥3.27 — wir pinnen auf ^8.1.0 falls SDK älter, sonst 8.x

## Architektur (baut auf navigation_interfaces.dart auf)

```
lib/services/routing/
  osrm_routing_service.dart      // implements RoutingService (fastest)
  brouter_routing_service.dart   // implements RoutingService (trail/trekking/moped)
  valhalla_routing_service.dart  // implements RoutingService (ebike-optimized)
  routing_provider.dart          // wählt Service nach RoutingPreference
lib/services/geocoding/
  photon_geocoding_service.dart  // search -> GeoLatLng list
lib/screens/map_screen.dart     // flutter_map UI
lib/widgets/
  route_option_sheet.dart        // BottomSheet: 2-3 Alternativen wählbar
  turn_by_turn_banner.dart       // nächstes Manöver oben
```

### Neue Domain-Erweiterung (navigation_interfaces.dart)
```dart
enum RoutingPreference { fastest, shortest, avoidHighways, trailPreferred }
// wird zu:
enum RoutingProfile {
  fastestCar,     // OSRM car
  trailForest,    // BRouter mtb — nur Waldwege/tracks bevorzugt
  scenicTrekking, // BRouter trekking
  ebikeOptimized, // Valhalla bicycle Mountain (Höhen-Costing)
}

class NavigationRoute { ... existing ...
  final List<GeoLatLng> geometry;        // Polyline-Punkte
  final double durationSeconds;
  final double elevationGainMetersTotal;
  final String providerName;             // 'osrm' | 'brouter' | 'valhalla'
}
```

### Energie-Prognose pro Route
EnergyProfile.calculateEnergyNeed() pro Segment → SOC-Ankunft-Prognose
im Route-Options-Sheet: „Ankunft: 61 % Akku" pro Alternative.
Nutzt gelernte Werte aus range_prediction_repository (Wh/km real).

## Features im Detail

### M1 — Karte & Standort (Fundament)
- [ ] pubspec: `flutter_map ^8.x`, `latlong2`
- [ ] MapScreen mit OSM-Tiles (UA-Header!), MyLocation-Layer via geolocator-Stream
- [ ] Navigation-Tab (5. Tab) in der Main-Navigation (portrait bottom-nav, landscape rail)
- [ ] Attribution „© OpenStreetMap contributors" PFLICHT (Legal!)

### M2 — Suche & Ziele
- [ ] Suchfeld → Photon-Debounce-Suche (300 ms), Ergebnisliste mit Name/Ort
- [ ] Tap-auf-Karte = Ziel setzen (Langdruck = Startpunkt überschreiben optional)
- [ ] „Mein Standort als Start"

### M3 — Multi-Provider-Routing
- [ ] RoutingService-Implementierungen (OSRM/BRouter/Valhalla) mit JSON-Parsing:
      Geometry-Polyline, Distanz, Dauer, Aufstieg (BRouter liefert's gratis mit)
- [ ] RoutingPreference → Provider-Mapping + Fallback-Kette
      (z.B. trailPreferred: BRouter mtb → wenn Fehler: Valhalla Mountain → OSRM)
- [ ] Alternatives=2-3 laden, im RouteOptionSheet anzeigen:
      Zeit, km, Höhenmeter, geschätzte Ankunfts-SOC, Anbieter-Tag
- [ ] Auswahl merken → Polyline auf Karte zeichnen

### M4 — Turn-by-Turn (leichtgewichtig)
- [ ] Valhalla-Manöver parsen (deutsche Texte!) → Liste
- [ ] TurnByTurnBanner: nächstes Manöver + Distanz-Delta aus GPS-Progress
- [ ] Fortschritt entlang der Polyline (Nearest-Point-Tracking, Off-Route-Detection > 30 m → Neuberechnung)

### M5 — E-Moto-Extras
- [ ] Reichweiten-Ring um aktuellen Standort (aus learned Wh/km + SOC)
- [ ] Höhenprofil-Chart unter der Route (fl_chart AreaChart, Daten aus BRouter/OTD)
- [ ] Warnung wenn Ankunfts-SOC < 15 %: „Ladestopp einplanen"

## Teststrategie (TDD)
- Unit: JSON-Parsing aller 3 Provider gegen echte gespeicherte Fixtures (curl-Dumps)
- Unit: Preference→Provider-Fallback-Kette
- Unit: Energie-Prognose pro Segment (bestehende EnergyProfile-Tests erweitern)
- Widget: RouteOptionSheet-Auswahl, Banner-Rendering
- redroid MCP: echter End-to-End — Suche „Chorin", Route, Landscape-Check

## Risiken & Gegenmaßnahmen
| Risiko | Maßnahme |
|--------|----------|
| Demo-Server Rate-Limits | Retry + Provider-Fallback; später eigener OSRM in docker-compose möglich (kostenlos!) |
| flutter_map 8.x braucht neues Flutter | Pin auf kompatible Version; Dockerfile hat Flutter 3.x — prüfen vor Upgrade |
| OSM-Tile-Policy (Bulk-Download verboten) | Nur sichtbare Kacheln laden, Cache begrenzen (flutter_map_cmap o.ä.) |
| GPS im Emulator = Berlin default | redroid: `adb emu geo fix` bzw. App-Location-Fake über Settings |

## Umsetzungsreihenfolge
M1 → M2 → M3 → (v2.7.0 Release) → M4 → M5 (v2.8.0)

Geschätzter Umfang M1–M3: ~1200 LOC + Tests. M4/M5 je ~400 LOC.
