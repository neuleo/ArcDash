# 17 — Ausführliche Denksession: E-Moto Map & Navigations-System (v3.2.0)

## Was ein Fahrer auf einem E-Motorrad (Sur-Ron / Arctic Leopard / FarDriver) wirklich braucht

Wenn man auf dem E-Bike/E-Moto sitzt und das Handy am Lenker montiert ist, hat man ganz andere Anforderungen als in einem Auto oder als Fußgänger:

### 1. Reale E-Moto Pain Points:
1. **Reichweitenangst (Range Anxiety) im Gelände:**
   - Ein reiner Kreis ist nett, aber die Realität ist: Bergauf verbraucht 3-mal mehr, Vollgas im Sand noch mehr.
   - Man braucht **3 Reichweiten-Zonen** auf der Karte:
     - 🟢 **Sicher (Eco / Trail):** Locker erreichbar
     - 🟡 **Normal / Grenzbereich:** Erreichbar bei diszipliniertem Fahren
     - 🔴 **Kritisch / Akku leer:** Nicht ohne Zwischenladen erreichbar
2. **Höhenprofil der Route vorab sehen:**
   - Wie viele Höhenmeter kommen auf den nächsten 10 km? Lohnt sich der Anstieg akkumäßig?
   - Interaktives **Elevation-Chart (Höhenprofil)** direkt in der Routenvorschau.
3. **Live Auto-Follow & Head-Up (Fahrtrichtung oben):**
   - Am Lenker will man, dass sich die Karte in Fahrtrichtung mitdreht (Heading-Follow), wenn man fährt, oder wahlweise nach Norden gelockt bleibt.
   - Der Zoom soll geschwindigkeitsabhängig mitskalieren (schnell = weiter rauszoomen, an Abbiegungen = reinzoomen).
4. **Live Turn-by-Turn Auto-Progress & Off-Route Re-Routing:**
   - Sobald man den GPS-Punkt passiert, muss der nächste Abbiegehinweis automatisch weiterschalten.
   - Wenn man falsch abbiegt (> 40 m abseits der Route), soll automatisch neu gerechnet werden.
5. **POIs für E-Fahrer (Kostenlose Ladesäulen & Steckdosen / Bike Parks / POIs):**
   - Overpass-API / OpenStreetMap Abfrage nach `amenity=charging_station`, `socket:schuko=yes` (für E-Moto Ladegeräte!), `leisure=park`.
6. **Cockpit-Mini-Overlay in der Karte:**
   - Live-Speed, Akku % und kW Leistung als dezentes HUD direkt auf der Karte oben links, damit man nicht zwischen Cockpit-Tab und Map hin- und herschalten muss.

---

## 🛠️ Konkreter Architektur- und Umsetzungsplan für v3.2.0:

### Baustein A: Live Navigation Engine & Auto-Follow (`NavigationEngine` & `MapStateNotifier`)
- GPS-Position wird kontinuierlich gegen die aktive Polyline gematcht.
- Automatische Berechnung:
  - Verbleibende Restdistanz & Restzeit
  - Distanz zum nächsten Manöver
  - Automatisches Weiterschalten des Manövers bei Annäherung (< 30 m)
  - Auto-Reroute Trigger bei Abweichung > 40 m
- Auto-Follow Mode: Zentriert die Karte stetig auf den Fahrer, optional mit Drehung in Fahrtrichtung (`bearing`).

### Baustein B: Höhenprofil-Chart Widget (`RouteElevationChart`)
- Nutzt `fl_chart`, um das Höhenprofil der ausgewählten Route als stylischen Gradient-LineChart darzustellen.
- Zeigt Minimal-, Maximal- und Gesamtaufstieg sowie den aktuellen Punkt auf der Route.

### Baustein C: 3-Zonen-Reichweiten-Layer (`RangeHeatmapLayer`)
- Zeichnet 3 transparente Kreisringe basierend auf:
  - Eco (100% Reichweite)
  - Normal (75% Reichweite)
  - Sport / Berg (50% Reichweite)
- Zeigt sofort auf einen Blick, wo der sichere Umkehrpunkt ist.

### Baustein D: E-Moto HUD Mini-Overlay auf der Karte (`MapCockpitOverlay`)
- Dezentes, transparentes Overlay oben links auf der Karte:
  - Große Speed-Anzeige (`km/h`)
  - Live Akku SOC `%`
  - Aktuelle Leistung `kW`
- Perfekt lesbar während der Fahrt am Lenker.

### Baustein E: E-Ladestationen & Steckdosen Finder (`ChargingStationService`)
- Kostenlose Overpass-API Abfrage für Schuko-Steckdosen und Ladesäulen im Umkreis.
- Anzeige als grüne Stecker-Pins auf der Karte mit 1-Tap als Navigationsziel.
