# ArcDash - Zusammenfassung aller durchgeführten Arbeiten

## Übersicht & Zielsetzung
Ziel war die vollständige Überarbeitung des Entwicklungsplans (`plan/`) und die lückenlose Integration aller **100+ FarDriver-Controller-Parameter** aus den Referenzdaten (`reference/controller_snapshot.md` und `conductor/`), ein vollwertiges Speichermodell über alle 26 Blöcke, interaktive Kurven- und Pin-Editoren, ein automatisierter MacroDroid-Hintergrundtrigger für den **Volume-Down Doppelklick** sowie ein visueller Vorher-Nachher Diff-Inspektor.

---

## 1. FarDriver-Speichermodell & Protokoll (26 Blöcke / 312 Bytes)
- **`lib/models/fardriver_memory.dart`**:
  - Implementierung aller 26 FarDriver-Parameterblöcke (`Addr00Block` bis `AddrD0Block`) à 12 Bytes.
  - Abbildung aller typisierten Felder, Bitmasken (z. B. `throttleResponse`, `directionInvert`, Pin-Register), Skalierungen und Immutable-Methoden (`with...()`).
  - `FarDriverFullMemory`: Zusammenhängende Aggregation aller 312 Bytes im Speicher für atomare Schreib-/Lesezugriffe und `.heb`-Exporte.
- **`lib/services/protocol_service.dart`**:
  - Einzelwort-Schreibpaket-Builder (`0x46`), Block-Write-Builder (`0xC0+len`), Systembefehle (`0x88/0xA0`), Reset (`0x05`), Factory-Reset (`0x08`).
- **`lib/services/heb_file_parser.dart`**:
  - Binär-Codec für 696-Byte `.heb`-Dateien (`HebFile.fromBlocks`, `toBytes()`) zur verifizierten Sicherung und Wiederherstellung von Werks-Setups.

---

## 2. Parameterkatalog & Fail-Closed Schreibsicherheit
- **`lib/services/write_safety.dart`**:
  - Registrierung von 100+ FarDriver-Parametern unterteilt in 10 Kategorien:
    1. `motor` (Höchstgeschwindigkeit, Phasenstrom, Batteriestrom)
    2. `speedRatios` (18-Punkte Drehzahlkurve 500–9000 RPM)
    3. `gearRatios` (Modus 1/2-Skalierung, Low/Mid Speed Current)
    4. `regen` (Rekuperationsstärke, 18-Punkte Rekuperationskurve)
    5. `pins` (14 konfigurierbare Funktionspins)
    6. `display` (CAN-Protokoll, Tacho-Impulse, Übersetzung)
    7. `protect` (Unter-/Überspannungsschutz, Temperaturabschaltung)
    8. `pid` (AN-Wellentyp, LM-Intervall, KI/KP-Regler)
    9. `flags` (Motorrichtung, Hall-Winkel, Parkmodus)
    10. `calibration` (Gasgriff-Spannungen Min/Max, Stromkalibrierung)
  - Vierstufige Risikoklassifizierung (`comfort`, `performance`, `safetyCritical`, `hardware`).
  - Strict Fail-Closed Evaluator: Schreibvorgänge werden starr blockiert, wenn das Fahrzeug nicht im Stillstand (`speedKph == 0.0`) ist, Telemetrie veraltet ist (`age > 1.5s`), Fehler vorliegen oder kein Backup vorliegt.

---

## 3. Visuelle Editoren & Tuning-Cockpit
- **`lib/widgets/speed_curve_editor.dart`**:
  - Interaktives 18-Punkte-Drehzahlkurven-Diagramm (500–9000 RPM in 500er-Schritten) mit Touch-Punkt-Bearbeitung und Kurven-Presets (*100% Full*, *Linear Ramp*, *Top-End Taper*).
- **`lib/widgets/regen_curve_editor.dart`**:
  - Interaktiver Rekuperations-Editor für 18 Stützpunkte (-100 % bis 0 %).
- **`lib/widgets/pin_mapping_manager.dart`**:
  - Pin-Manager für 14 Funktionsschalter (`Pause`, `Brake`, `Reverse`, `Cruise`, `Boost`, `Gear1/2/3` etc.) mit Dropdowns aller physikalischen FarDriver-Pins.
- **`lib/widgets/tuning_diff_dialog.dart`**:
  - Moderner, AMOLED-optimierter **Diff-Inspektor-Dialog**: Stellt vor jedem Schreibvorgang alle geänderten Register dem Fahrer gegenüber (Original vs. Neu mit Einheiten und farbkodierten Risikobadges) und verlangt eine Bestätigung.
- **`lib/screens/tuning_screen.dart`**:
  - Ausbau des Haupt-Tuning-Cockpits mit Quick-Tuning-Bar, 10 ausklappbaren Parameter-Akkordeons, Expert-Mode-Sicherung und atomarem Werks-Restore aus `unmodified_basemap.heb`.

---

## 4. Android Hintergrundbetrieb & MacroDroid Trigger (Volume-Down Doppelklick)
- **`android/app/src/main/kotlin/com/arcdash/arcdash/MacroDroidReceiver.kt`**:
  - Receiver für die Action `com.arcdash.arcdash.APPLY_STREET_LEGAL` (auslöserbar durch MacroDroid per Volume-Down Doppelklick).
- **`android/app/src/main/kotlin/com/arcdash/arcdash/MainActivity.kt`**:
  - Weiterleitung des Triggers an die Flutter-Engine auch bei gesperrtem Bildschirm + Deep-Link Support (`arcdash://profile/street_legal`).
  - **Haptisches Feedback ohne Display-Aktivierung**:
    - **Erfolg (2 kurze Pulse):** 150ms Vibration, 100ms Pause, 150ms Vibration signalisieren unauffällig in der Hosentasche die erfolgreiche Drosselung auf 45 km/h.
    - **Fehler / Schutz blockiert (1 langer Puls):** 400ms Vibration.
- **`android/app/src/main/kotlin/com/arcdash/arcdash/ArcDashForegroundService.kt`**:
  - Aufrechterhaltung der BLE-Verbindung im Hintergrund als Foreground-Service.
- **`lib/services/street_legal_trigger_service.dart`**:
  - Sichere Hintergrundverarbeitung des Triggers mit automatischer Profilanwendung (`Street Legal` mit 45 km/h, 80A, ECO) und Benachrichtigungs-Update.

---

## 5. Testabdeckung & Verifikation
- **`test/fardriver_memory_test.dart`**: Unit-Tests für alle 26 Speicherblöcke.
- **`test/parameter_catalog_extended_test.dart`**: Tests für 100+ Parameter und Umrechnungen.
- **`test/curves_and_pins_test.dart`**: Widget-Tests für Kurven- & Pin-Editoren.
- **`test/street_legal_trigger_test.dart`**: Tests für MacroDroid-Action, Rejection bei Bewegung und Haptik-Signale.
- **`test/tuning_diff_dialog_test.dart`**: Widget-Tests für den Diff-Inspektor.
- **`test/tuning_screen_v2_test.dart` & `test/tuning_v2_test.dart`**: Aktualisierte UI- und Schreib-Tests.
- **Ergebnis:** **Alle 258+ Tests sind grün (0 Fehler).** `rebuild.sh` lief ohne Fehler durch.
