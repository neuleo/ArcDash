# Phase 5: Profil- & Backup-System (.HEB & JSON)

## Phasenziel

Profile sind versionierte, hardwarekompatible Parametersätze. ArcDash unterstützt die native Speicherung aller Parameterkategorien, den Import/Export sowohl im modernen JSON-Format als auch im originalen binären FarDriver `.heb`-Format (696 Bytes), atomaren Werks-Restore und einen optimierten Fast-Path für "Street Legal".

---

## T038 - Versioniertes Profilmodell für vollständige Parameterkonfigurationen

**Referenz:** [`lib/models/tuning_profile.dart`](../lib/models/tuning_profile.dart)

### Arbeitsumfang
- Speicherung aller Kategorien:
  - Fahrdynamik (Max Speed, Line/Phase Current, Throttle Response, Boost Timer)
  - 18-Punkte Drehzahl-Leistungskurve (500 bis 9000 RPM)
  - 18-Punkte Rekuperationskurve (500 bis 9000 RPM)
  - Modus 1 (DL) und Modus 2 (DM) Strombegrenzungen
  - Pin-Belegungen (14 konfigurierbare Pins)
  - Schutzparameter (Voltages, Temps, Timeouts)
  - PID-Parameter & Feldschwächung
- Unterstützung für vollständige Profile und minimale Teil-Profile (z. B. nur Geschwindigkeitsdrossel).

---

## T039 - Integrierte Presets definieren

### Enthaltene Werks- & Praxis-Presets:
1. **Stock Offroad**: Originale Werksabstimmung (125 km/h, 200 A Line, 450 A Phase, Sport-Kurve).
2. **Street Legal**: Streng verkehrskonforme Abstimmung (z. B. 45 km/h, moderater Strom, sanfte Gasannahme, EABS aktiv).
3. **Eco Range**: Maximale Reichweite und Effizienz (45 km/h, 100 A Line, ECO-Kurve, starke Rekuperation).
4. **Trail / Enduro**: Feinfühlige Gasannahme für schweres Gelände, reduziertes Anfahr-Drehmoment gegen Durchdrehen.
5. **Extreme Sport**: Maximale Beschleunigung, voller Phasenstrom und erweiterte Feldschwächung für abgesperrte Strecken.

---

## T040 - Profilverwaltung & Diff-Ansicht

**Referenz:** [`lib/services/profile_manager.dart`](../lib/services/profile_manager.dart), [`lib/screens/tuning_screen.dart`](../lib/screens/tuning_screen.dart)

### Arbeitsumfang
- CRUD-Operationen für eigene Presets (Erstellen, Umbenennen, Duplizieren, Löschen).
- Interaktive **Diff-Vorschau**: Vor dem Schreiben sieht der Nutzer exakt, welche Werte sich gegenüber dem Ist-Zustand des Controllers ändern.

---

## T041 - .HEB-Binär-Parser & Generator (696 Bytes)

**Referenz:** [`lib/services/heb_file_parser.dart`](../lib/services/heb_file_parser.dart)

### Arbeitsumfang
- Bidirektionales Format:
  - 26 Parameterblöcke à 12 Bytes = 312 Bytes
  - 1 CAN-Konfigurationsblock à 384 Bytes
  - Gesamtgröße: exakt 696 Bytes
- Ermöglicht das Laden und Speichern von Backups, die 1:1 kompatibel mit der offiziellen PC-Software und App sind.

---

## T042 - Werks-Restore aus `unmodified_basemap.heb`

**Referenz:** [`lib/services/stock_heb_restore.dart`](../lib/services/stock_heb_restore.dart)

### Arbeitsumfang
- Ein-Klick-Wiederherstellung aller 156 Register aus der im Asset eingebetteten Werks-Basemap.
- Schutz durch Sicherheitsabfrage und Stillstandsprüfung.

---

## T043 - Street-Legal-Fast-Path optimieren

### Arbeitsumfang
- Optimierter Schreibpfad, der nur die minimal erforderlichen Register (SpeedLimit, Line Current, Throttle Mode) verändert.
- Dauer: unter 2 Sekunden.
- Ermöglicht den Aufruf im Hintergrund ohne Displayaktivierung über den MacroDroid-Trigger.
