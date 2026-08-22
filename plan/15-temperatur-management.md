# Plan 15: Temperatur-Management, BMS-Warnungen & Statistik-Ausbau

**Version-Ziel:** v2.5.0
**Status:** IN ARBEIT
**Erstellt:** 2026-08-22 (AI Manager, nach Web-Recherche)

---

## 🔬 Recherche-Basis (Quellen)

### Battery University BU-502 (Discharging at High and Low Temperatures)
- Bei **–20 °C sind die meisten Batterien nur bei ~50 % Leistungslevel**
- Entladetemperaturbereich Li-ion: **–20 °C bis 60 °C**
- Innere Widerstand steigt bei Kälte stark an → Spannungseinbruch unter Last

### Battery University BU-410 (Charging at High and Low Temperatures)
- **Kein Laden unter 0 °C erlaubt** (Lithium-Plating-Gefahr → permanente Degradation!)
- Bei –30 °C ist nur noch 0.02C Ladestrom zulässig
- Rekuperation = Laden → **unter 0 °C ist Rekuperationsleistung gefährlich!**

### Wikipedia Lithium-ion battery / LFP
- Lithium Plating wird durch niedrige Temperaturen + hohe Ladeströme verstärkt
- Hohe Temperaturen (>30 °C) reduzieren Zyklusleben um 20 %, >40 °C um 40 %

### Chemie-Hinweis Arctic Leopard XE Pro
Der Pack des Users lädt auf 4.187 V/Zelle × 20 = 83.7 V → das ist **NMC-Chemie** (nicht LFP).
→ Implementierung als **konfigurierbares Chemie-Profil** (NMC default, LFP wählbar).

---

## ⚡ Feature 1: Feinstufige Max-kW-Leistung nach Akkutemperatur

### Datei: `lib/utils/battery_temp_power.dart` (NEU)

```dart
/// Ankerpunkte: Zulässige Leistung als % des Nenn-Maxwerts bei Temp.
/// Zwischen Ankerpunkten LINEAR interpolieren (feinstufig, 0.1°C Auflösung)!
```

**NMC-Ankerpunkte (default, entspricht Arctic Leopard XE Pro 20S-Pack):**
| Temp (°C) | Max Power % |
|-----------|-------------|
| -20 | 25 |
| -15 | 32 |
| -10 | 42 |
| -5 | 55 |
| 0 | 68 |
| 5 | 80 |
| 10 | 90 |
| 15 | 96 |
| 20 | 100 |
| 25 | 100 |
| 30 | 98 |
| 35 | 96 |
| 40 | 92 |
| 45 | 85 |
| 50 | 75 |
| 55 | 60 |
| 60 | 45 |

**LFP-Ankerpunkte (optional wählbar):**
| Temp (°C) | Max Power % |
|-----------|-------------|
| -20 | 20 |
| -10 | 38 |
| 0 | 62 |
| 10 | 85 |
| 20 | 100 |
| 30 | 100 |
| 45 | 95 |
| 55 | 80 |
| 60 | 70 |

**API:**
```dart
class BatteryTempPower {
  /// Gibt zulässige Max-Leistung in kW bei gegebener Zelltemperatur zurück.
  /// Interpoliert linear zwischen Ankern (0.1°C-fein).
  static double maxPowerKwAt(double tempC, {double ratedMaxKw = 12.0, BatteryChemistry chem = BatteryChemistry.nmc});
  
  /// Prozentwert (0..100) der verfügbaren Leistung.
  static double availablePercent(double tempC, {BatteryChemistry chem});
}
```

### Tests (`test/battery_temp_power_test.dart`, NEU)
- [ ] Exakte Ankerpunkte werden 1:1 zurückgegeben (z.B. -10°C NMC → 42 %)
- [ ] Zwischenwerte feinstufig interpoliert (-7.3°C → exakter Linearwert zwischen -10 und -5)
- [ ] Unter -20°C und über 60°C wird geklemmt (keine Werte > Anker-Ränder)
- [ ] NMC vs LFP Profile unterscheiden sich korrekt
- [ ] ratedMaxKw Multiplikator korrekt (z.B. 12 kW * 0.68 @ 0°C = 8.16 kW)

---

## 🌡️ Feature 2: Batterietemperatur im Standard-Dashboard

### Änderungen: `lib/screens/dashboard_screen.dart`, Dashboard-Katalog

- [ ] Neue DashboardMetric `batteryTemperature` im Metrik-Katalog registrieren
- [ ] Tile zeigt Motor-/Batterie-Temp (von ANT BMS NTCs bevorzugt, Fallback Controller-Temp)
- [ ] Farbcodierung: Grün (<40°C), Gelb (40–55°C), Rot (>55°C), Blau (<5°C kalt)
- [ ] Im Default-Portrait- UND Default-Landscape-Layout enthalten

## ⚠️ Feature 3: Vollbild-Temperaturwarnung

### Datei: `lib/widgets/temp_warning_overlay.dart` (NEU)

**Auslösebedingungen:**
1. **ZU KALT**: Akku-Temp < 0 °C → VOLLBILD-WARNUNG:
   - Titel: `⚠️ AKKU ZU KALT`
   - Text: "Hohe Last und Rekuperation können den Akku bei X °C dauerhaft schädigen (Lithium-Plating)."
   - Empfehlung: "Max. Y kW fahren. Akku vor Volllast aufwärmen."
   - Live angezeigter Wert: `Max Leistung jetzt: Y kW`
   - Hintergrund-Pulsieren orange/blau, dismissbar für 5 Min (Timer), danach wieder sichtbar solange kalt
2. **REGEN-WARNUNG** bei Temp < 0 °C zusätzlich: Rekuperation deaktivieren/warnen
3. **ZU HEISS**: Akku-Temp > 55 °C → VOLLBILD-WARNUNG rot:
   - "Akku überhitzt (X °C). Fahrt pausieren, Akku abkühlen lassen."

**Regeln:**
- Overlay als `Stack`-Layer ÜBER dem gesamten Dashboard (alle Tabs!)
- Nur anzeigen wenn App verbunden + Telemetrie frisch (< 30 s)
- Hysterese: Warnung aus bei > +2 °C über Schwelle (verhindert Flackern)
- Einstellbare Schwellen in Settings (default: kalt 0 °C, heiß 55 °C)

### Tests (`test/temp_warning_test.dart`, NEU)
- [ ] Overlay erscheint bei -1°C, nicht bei +1°C
- [ ] Hysterese funktioniert (aus bei +2°C nach Warnung)
- [ ] Max-kW-Wert im Overlay korrekt berechnet
- [ ] Overlay nicht sichtbar bei getrennter Verbindung
- [ ] Heiß-Warnung bei 56°C erscheint

---

## 🔔 Feature 4: BMS-Warnsystem

### Datei: `lib/services/bms_alert_service.dart` (NEU)

**Warnregeln (prüfen bei jedem BMS-Frame):**
1. Zell-Delta > 50 mV → Warnstufe ORANGE: "Zellen driften auseinander (X mV)"
2. Einzelzell-Spannung < 3200 mV → ROT: "Zelle N tiefentladen!"
3. Einzelzell-Spannung > 4200 mV → ROT: "Zelle N Überladung!"
4. BMS-NTC-Temp > 55 °C → ROT: "Akku-Temperatur kritisch"
5. BMS-NTC-Temp < 0 °C → BLAU/ORANGE: Kalte-Warnung (wie Feature 3)

**Integration:**
- Warnungen in bestehende `FaultHistoryRepository` schreiben (Typ bmsAlert)
- SnackBar/Banner im Cockpit bei aktiver Warnung
- Badge-Zähler im Cockpit-Header (neben LIVE-Badge)

### Tests (`test/bms_alert_service_test.dart`, NEU)
- [ ] Jede Regel löst korrekt aus (Delta 51 mV ja, 49 nein)
- [ ] Keine Duplikate innerhalb 60 s (Debounce)
- [ ] FaultHistory-Einträge entstehen
- [ ] Grenzwerte genau testen (3200/4200 mV, 55 °C)

---

## 📊 Feature 5: Fahrten-Statistiken vertiefen (stats_screen.dart)

- [ ] Wochen-/Monatsaggregation über Session-Historie (gefahren km, Wh/km, Top-Speed, Fahrzeit)
- [ ] Balkendiagramm letzte 14 Tage km (fl_chart, vorhanden)
- [ ] Liniendiagramm Verbrauch (Wh/km) Verlauf über Sessions
- [ ] Effizienz-Vergleich: aktuelle Session vs. persönlicher Durchschnitt ("12 % effizienter als Ø")
- [ ] Bestwerte-Karten: längste Fahrt, höchste Reichweite, beste Effizienz

### Tests
- [ ] Aggregation korrekt (Wochen/Monate)
- [ ] Effizienz-Delta-Berechnung stimmt
- [ ] Leere Historie zeigt sauberen Empty-State

---

## 🎨 Feature 6: Dashboard-Politur (Layout-Editor)

- [ ] Neuer Tile-Typ: `bmsCellDelta` (Min/Max/Delta mV kompakt, grün/orange)
- [ ] Neuer Tile-Typ: `speedGpsVsMotor` (GPS-Speed vs. Motor-Speed nebeneinander, Abweichung %)
- [ ] Beide Tiles im Katalog + Validierung + Default-Layouts NICHT verändern (nur verfügbar machen)

### Tests
- [ ] Tile-Validierung akzeptiert neue Typen
- [ ] Roundtrip Persistenz
- [ ] Renderer zeichnet beide Tiles unabhängig

---

## ✅ Abschluss-Kriterien (Definition of Done)

1. Alle neuen Tests GRÜN + bestehende 287 Tests unverändert GRÜN
2. `docker compose run --rm flutter dart format lib test` ohne Änderungen
3. Version bump auf 2.5.0+1 in pubspec.yaml
4. Commit + Push → Release-Build über GitHub Actions
5. AI Manager verifiziert APK-Upload via 5-Minuten-Regel
