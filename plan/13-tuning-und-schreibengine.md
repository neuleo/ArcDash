# Phase 12-17: Version 2 — Schreibengine, Tuning & Werks-Restore

Diese Phasendatei spezifiziert die Umsetzung von **Version 2** für ArcDash: Das sichere Schreiben von Parametern in den FarDriver-Controller, ein dedizierter **Tuning-Tab** in der Hauptnavigation, ein **Werks-Restore aus der `Unmodified Basemap.heb`** sowie **Read-Back-Verifikation**.

---

## Phase 12: Haupt-Navigation & UI-Struktur

### T086 - 4-Tab-Hauptnavigation etablieren
**Abhaengigkeiten:** T054  
**Hardware erforderlich:** Nein  

#### Arbeitsumfang
- Erweitere `lib/screens/app_shell.dart` um ein 4-Tab-Layout:
  1. `Cockpit` (Dashboard & Telemetrie)
  2. `Tuning` (Parameter-Steuerung & Presets)
  3. `Fahrten` (Session-Historie & Statistiken)
  4. `Einstellungen` (Verbindung, Kalibrierung, Dev-Tools)
- Passe sowohl Hochformat (`NavigationBar`) als auch Querformat (`NavigationRail`) nahtlos an.

#### Tests und Akzeptanz
- Alle 4 Tabs lassen sich umschalten.
- Der aktive Tab wird optisch hervorgehoben (Neon-Grün).
- Keine UI-Overflows im Hoch- oder Querformat.

---

### T087 - TuningScreen als eigener Tab ausbauen
**Abhaengigkeiten:** T086  
**Hardware erforderlich:** Nein  

#### Arbeitsumfang
- Integriere den `TuningScreen` direkt als Haupt-Screen des `Tuning`-Tabs.
- Zeige Safety-Banner, Preset-Auswahl, Parameter-Slider (Max Speed, Line Current, Throttle Response) und Restore-Optionen an.

#### Tests und Akzeptanz
- Der Screen passt sich flexibel an Bildschirmgrößen an.
- Alle UI-Elemente sind barrierefrei und gut lesbar.

---

## Phase 13: Fail-Closed Safety Engine & Parameterkatalog

### T088 - Fail-Closed Safety Evaluator bauen
**Abhaengigkeiten:** T031, T087  
**Hardware erforderlich:** Nein (mit Fake Transport simulierbar)  

#### Arbeitsumfang
- Baue einen universellen Safety-Evaluator in der Schreibengine:
  - Schreiben ist **ausschließlich** erlaubt, wenn:
    1. BLE-Verbindung aktiv ist (`connected`).
    2. Das Fahrzeug steht (`speedKph == 0.0`).
    3. Die Telemetrie frisch ist (`maxAge < 1.5s`).
    4. Keine Fehler/Faults im Controller vorliegen (`!hasAnyFault`).
- Liefere typisierte Ablehnungsgründe (z.B. `vehicle_moving`, `telemetry_stale`, `fault_active`) für UI und Audit-Log.

#### Tests und Akzeptanz
- Bei Geschwindigkeit > 0.5 km/h oder Trennung wird der Schreibvorgang sofort blockiert.
- Der Benutzer sieht einen klaren Hinweis, warum der Vorgang gesperrt ist.

---

### T089 - Parameterkatalog & Hardwaregrenzen aus Basemap festlegen
**Abhaengigkeiten:** T030, T088  
**Hardware erforderlich:** Nein  

#### Arbeitsumfang
- Leite die sicheren Parametergrenzen aus der `reference/basemaps/unmodified_basemap.json` ab:
  - **Max Speed (`Addr12 / 0x15`)**: 10 bis 130 km/h (Werksstandard 125 km/h)
  - **Max Line Current / Akkugrenzstrom (`Addr18 / 0x19`)**: 10 bis 300 A (Werksstandard 200 A)
  - **Throttle Response / Gasannahme (`Addr18 / 0x19`)**: Eco (0), Trail (1), Sport (2), Race (3)
- Definiere Skalierungsformeln und Byte-Masken.

#### Tests und Akzeptanz
- Parameter außerhalb der Hardware-Grenzen werden vom Validator abgelehnt.
- Alle Werte konvertieren exakt zwischen SI-Einheiten (km/h, A) und FarDriver-Byte-Formaten.

---

## Phase 14: Presets & Live-Tuning

### T090 - Live-Tuning Slider & Parameter-Steuerung
**Abhaengigkeiten:** T088, T089  
**Hardware erforderlich:** Ja fuer reale BLE-Schreibtests  

#### Arbeitsumfang
- Verbinde die Slider im `TuningScreen` mit den Schreib-Methoden von `ProtocolService`:
  - `setMaxSpeedPacket(maxSpeedKph)`
  - `setMaxLineCurrPacket(maxLineCurrA)`
  - `setThrottleResponsePacket(mode)`
- Sende die Kommandos serialisiert über die `CommandQueue`.

#### Tests und Akzeptanz
- Slider lassen sich flüssig bedienen.
- Nach Stillstands-Prüfung wird das Schreibpaket gesendet.

---

### T091 - Tuning-Presets System
**Abhaengigkeiten:** T090  
**Hardware erforderlich:** Nein  

#### Arbeitsumfang
- Baue konfigurierbare Presets:
  - `Stock Offroad`: 125 km/h / 200 A / Sport
  - `Eco Range`: 45 km/h / 100 A / Eco
  - `Custom`: Benutzerdefiniert
- Erlaube 1-Klick-Laden & Vorschau aller Parameter vor dem Schreiben.

#### Tests und Akzeptanz
- Wechsel zwischen Presets aktualisiert die Slider-Vorschau instantan.

---

## Phase 15: Werks-Restore & Read-Back Verifikation

### T092 - Werks-Restore Engine (aus `Unmodified Basemap.heb`)
**Abhaengigkeiten:** T090, T091  
**Hardware erforderlich:** Ja fuer Flashen  

#### Arbeitsumfang
- Implementiere einen **"Werkseinstellungen wiederherstellen"**-Button.
- Lade die `assets/basemaps/unmodified_basemap.heb` und flashe alle Parameter-Blöcke atomar zurück in den Controller.

#### Tests und Akzeptanz
- Der Benutzer muss den Vorgang in einem Sicherheitsdialog bestätigen.
- Alle Werksregister werden nacheinander geschrieben.

---

### T093 - Read-Back Verifikation & Erfolgs-Quittung
**Abhaengigkeiten:** T092  
**Hardware erforderlich:** Ja  

#### Arbeitsumfang
- Lies nach dem Schreiben die Register über den Status-Stream zurück.
- Vergleiche geschriebenen Wert mit dem im Controller aktiven Wert.
- Zeige in der UI einen grünen Bestätigungs-Haken ("Verifiziert").

#### Tests und Akzeptanz
- Wenn Read-back übereinstimmt, erscheint die Bestätigung.
- Bei Abweichung erscheint ein Warnhinweis.

---

## Phase 16 & 17: Qualitätssicherung & Release (v2.0.0)

### T094 - Unit- & Widget-Tests erweitern
**Abhaengigkeiten:** T086 bis T093  
**Hardware erforderlich:** Nein  

#### Arbeitsumfang
- Teste alle neuen Schreibengine-, Safety- und Restore-Funktionen im Docker-Container.

### T095 - Release v2.0.0 auf GitHub Actions veröffentlichen
**Abhaengigkeiten:** T094  
**Hardware erforderlich:** Nein  

#### Arbeitsumfang
- Tagge das Release als `v2.0.0` und verifiziere den APK-Build über die GitHub API.
