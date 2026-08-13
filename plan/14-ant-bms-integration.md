# Phase 18: ANT-BMS Bluetooth-Integration & Dual-BLE Auto-Remember

Diese Phasendatei spezifiziert die Anbindung von **ANT BMS Akkusystemen** über Bluetooth Low Energy, das Auslesen von Einzelzellspannungen, Zell-Drift und Akkutemperaturen sowie den automatischen **Dual-BLE Auto-Remember** für FarDriver-Controller und ANT-BMS.

---

## Phase 18: ANT-BMS Protokoll, Dual-BLE & Auto-Remember

### T102 - ANT-BMS Protokoll-Decoder & Data Model bauen
**Abhaengigkeiten:** T010, T014  
**Hardware erforderlich:** Nein (Paket-Fixtures)  

#### Arbeitsumfang
- Erstelle `lib/models/ant_bms_state.dart` für Zellspannungen (Cell 1..N), Min/Max-Zellspannung, Zell-Delta (mV), Akku-Temperaturen, BMS-SOC (%) und MOSFET-Schaltzustände.
- Erstelle `lib/utils/ant_bms_parser.dart`:
  - Decodierung der ANT BMS Frames (`0x7E 0xA1 ... 0x55`).
  - Modbus CRC16 Überprüfung (`calcCrc16`).
  - Extraktion aller Zellspannungen (mV) und NTC-Temperaturen.

#### Tests und Akzeptanz
- CRC16-Golden-Tests verifizieren dekodierte ANT-BMS Frames.
- Zellspannungen und Temperaturen werden korrekt extrahiert.

---

### T103 - Dual-BLE Transport & ANT-BMS Service bauen
**Abhaengigkeiten:** T017, T020, T102  
**Hardware erforderlich:** Ja (ANT BMS BLE Gerät)  

#### Arbeitsumfang
- Baue `lib/services/ant_bms_service.dart` und `AntBmsNotifier`:
  - Parallele BLE-Verbindung zu `ANT@BLE...` Geräten (Service `ffe0`, Char `ffe1`).
  - Periodische Statusabfrage (`0x7E 0xA1 0x01 ...`).
  - Parallele Aufrechterhaltung der FarDriver-Controller-Verbindung ohne gegenseitige Blockierung.

#### Tests und Akzeptanz
- Fake-Transport-Tests verifizieren die simultane Verbindungsführung von Controller + BMS.

---

### T104 - Dual-BLE Auto-Remember (Dauerhafte Auto-Verbindung)
**Abhaengigkeiten:** T021, T103  
**Hardware erforderlich:** Nein  

#### Arbeitsumfang
- Erweitere `StorageService` um `saveLastBmsId` und `loadLastBmsId`.
- Implementiere Auto-Connect für **beide** Geräte beim App-Start:
  - Wenn `lastConnectedController` vorhanden ist ➔ automatisches Verbinden im Hintergrund.
  - Wenn `lastConnectedBms` vorhanden ist ➔ automatisches Verbinden im Hintergrund.

#### Tests and Akzeptanz
- App-Start stellt Verbindungen zu beiden gemerkten Bluetooth-Geräten automatisch wieder her.

---

### T105 - Zellspannungs- & BMS-Monitor Widget bauen
**Abhaengigkeiten:** T103  
**Hardware erforderlich:** Nein  

#### Arbeitsumfang
- Erstelle ein interaktives **BMS-Zellen-Widget** im `Cockpit` und `Settings`:
  - Balkendiagramm aller Einzelzellen (Cell 1..20).
  - Farbkodierung für ausbalancierte (grün) vs. abweichende Zellen (orange/rot).
  - Anzeige von Max-Zelle, Min-Zelle und Delta (mV).

#### Tests und Akzeptanz
- Widget rendert Einzelspannungen und hebt abweichende Zellen optisch hervor.
