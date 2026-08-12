# Phase 6: Multi-Kategorie Tuning-UI & Visuelle Editoren

Diese Phasendatei spezifiziert das **Tuning-Cockpit** in ArcDash. Es ersetzt die unübersichtliche chinesische Original-App durch eine hochmoderne, AMOLED-optimierte Benutzeroberfläche mit interaktiven Kurven-Editoren, Pin-Manager und geschütztem Experten-Modus.

---

## T086 - 4-Tab-Hauptnavigation etablieren
**Status:** [x] Abgeschlossen  
**Referenz:** [`lib/screens/app_shell.dart`](../lib/screens/app_shell.dart)

- `Cockpit`: Live-Telemetrie, Leistungsbogen, GPS-Speed, Reichweite.
- `Tuning`: Parameter-Steuerung, Presets, Kurven-Editoren.
- `Fahrten`: Session-Statistiken & GPS-Fahrtenhistorie.
- `Einstellungen`: Verbindung, Diagnose, Einheiten, Kalibrierung.

---

## T087 - TuningScreen als modulares Haupt-Cockpit
**Status:** [x] Abgeschlossen / Im Ausbau  
**Referenz:** [`lib/screens/tuning_screen.dart`](../lib/screens/tuning_screen.dart)

---

## T096 - Quick-Tuning Bar für Alltags-Fahrer

### Arbeitsumfang
- Schneller Zugriff auf die wichtigsten Fahrparameter:
  - **Fahrmodus-Presets**: 1-Tap-Umschaltung zwischen *Stock Offroad*, *Street Legal*, *Eco Range*, *Trail*, *Sport*.
  - **Max Speed**: Slider mit Sofortanzeige in km/h.
  - **Peak Power & Line Current**: Slider in kW / Amps.
  - **Throttle Response**: Schnellauswahl zwischen *Line (Race)*, *Sport*, *Eco*.
  - **Rekuperations-Stärke**: Bremsenergierückgewinnung in %.

---

## T097 - 10-Kategorien Parameter-Matrix

### Arbeitsumfang
Strukturierung aller 100+ FarDriver-Parameter in übersichtliche, einklappbare Akkordeons / Unter-Tabs:
1. **Fahrdynamik & Motor-Grundparameter** (Rated Speed/Voltage/Power, BackSpeed, Acc/Dec Steps).
2. **Drehzahl-Leistungskurve (Ratios in Speed)**: 18 Stützpunkte von 500 bis 9000 RPM.
3. **Rekuperations-Kurve (Energy Regen)**: 18 Stützpunkte von 500 bis 9000 RPM.
4. **Gangstufen & Geschwindigkeitsmodi**: Modus 1 (DL), Modus 2 (DM), Modus 3/4 (DH/Boost).
5. **Hardware-Pins & Funktionsschalter**: Konfiguration aller 14 physikalischen Controller-Pins.
6. **Display-, Tacho- & CAN-Bus-Konfiguration**: Reifengrößen, Tacho-Impulse, CAN-Baudrate.
7. **Schutzgrenzen & Abschaltungen**: Unter-/Überspannung, Motor-/MOSFET-Temperaturschutz.
8. **PID-Regler & Feldschwächung**: AN (Wave Type), LM (Wave Interval), Start/Mid/Max KI & KP.
9. **Spezialfunktionen & Produkt-Flags**: Rückwärtsgang, Parkbremse, Anti-Theft, EABS, Follow-Mode.
10. **Kalibrierung & Diagnose**: ADC-Nullpunkte, Phasenstrom-Koeffizienten, Speicherzyklen.

---

## T098 - Interaktiver 18-Punkte Drehzahlkurven-Editor

### Arbeitsumfang
- Visueller Chart-Editor für die 18 Drehzahl-Stützpunkte (500 bis 9000 RPM in 500er-Schritten).
- Touch-Bedienung: Punkte können direkt auf der Kurve oder über dedizierte Schieberegler angepasst werden.
- Kurven-Vorlagen: *Linear*, *Aggressive Power*, *Smooth Eco*, *Top-End Weakening*.

---

## T099 - Interaktiver Rekuperationskurven-Editor

### Arbeitsumfang
- Visueller Chart-Editor für die Rekuperationsströme (-% bis 0%) über das gesamte Drehzahlspektrum (500 bis 9000 RPM).
- Visualisierung in Kontrast-Grün/Cyan zur intuitiven Unterscheidung von Antriebsleistung.

---

## T100 - Pin- & Hardware-Funktions-Manager

### Arbeitsumfang
- Übersichtliche Matrix für alle 14 programmierbaren Anschlusspins des FarDriver-Controllers (Pause, SideStand, Cruise, Boost, LowSpeed, HighSpeed, Reverse, Forward, SwitchVol, Seat, AntiTheft, Charge, SpeedLimit, Repair).
- Dropdown-Auswahl mit validierten Pin-Optionen (`NC`, `PIN2`, `PIN3`, `PIN5`, `PIN8`, `PIN9`, `PIN14`, `PIN15`, `PIN17`, `PIN18`, `PIN24`, `PD1`, `PB4`, `Invalid`).

---

## T101 - Expert-Mode Guardrails & Vorher-Nachher Diff-Dialog

### Arbeitsumfang
- **Experten-Schutzschalter**: Hardwarekritische Parameter (z. B. Polpaare, Pin-Mappings, Phasenwinkel) sind standardmäßig gesperrt und werden erst nach Bestätigung eines Warnhinweises editierbar.
- **Diff-Inspektor**: Vor dem Schreiben auf den Controller öffnet sich ein übersichtlicher Dialog, der jede geänderte Eigenschaft (Alter Wert → Neuer Wert) farblich hervorhebt.
- **Live-Verifikation**: Nach erfolgreichem Schreiben und Read-Back erscheint ein grüner Bestätigungshaken.
