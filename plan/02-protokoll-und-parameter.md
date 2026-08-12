# Phase 2: FarDriver-Protokoll & Speichermodell (Vollständige Snapshot-Abdeckung)

## Phasenziel

Das FarDriver-Protokoll wird in vollem Umfang implementiert. Das Speichermodell deckt alle 26 Adressblöcke (`0x00` bis `0xD0` sowie Status-/Telemetrieblöcke `0xD6`, `0xDC`, `0xE2`, `0xE8`, `0xEE`, `0xF4`, `0xFA`) ab. Alle 100+ Parameter aus dem Original-Snapshot (`reference/controller_snapshot.md`) werden typisiert, skaliert und bit-genau abgebildet.

---

## T009 - Protokoll-Belegmatrix erstellen
**Status:** [x] Abgeschlossen  
**Referenz:** [`plan/protokoll-belegmatrix.md`](./protokoll-belegmatrix.md)

### Arbeitsumfang
- Vollständige Erfassung aller 26 FarDriver-Blöcke (312 Bytes Parameter + 384 Bytes CAN = 696 Bytes HEB).
- Zuordnung aller Parameter zu Adressen, Offsets, Masken, Shifts und Skalierungsformeln.

---

## T010 - BLE-Captures und Paket-Fixtures definieren
**Status:** [x] Abgeschlossen  
**Referenz:** [`lib/models/protocol_fixture.dart`](../lib/models/protocol_fixture.dart)

---

## T011 - CRC durch Golden-Tests absichern
**Status:** [x] Abgeschlossen  
**Referenz:** [`lib/utils/crc_calculator.dart`](../lib/utils/crc_calculator.dart)

---

## T012 - Fragmentierungsfesten Paket-Framer bauen
**Status:** [x] Abgeschlossen  
**Referenz:** [`lib/utils/packet_framer.dart`](../lib/utils/packet_framer.dart)

---

## T013 - Vollständiges 26-Block FarDriver-Speichermodell abbilden
**Status:** [x] In Überarbeitung / Ausbau  
**Referenz:** [`lib/models/fardriver_memory.dart`](../lib/models/fardriver_memory.dart)

### Arbeitsumfang
- Erweitere `fardriver_memory.dart` auf alle 26 Blöcke:
  - `Addr00Block` (Kalibrierung, Spannungs- & Phasenstromkoeffizienten)
  - `Addr06Block` (MorseCode, SpeedKI/KP, ThrottleLow/High, FAIF, CurveTime, TempSensor, Brake, Direction)
  - `Addr0CBlock` (PhaseOffset, Zero/Full BattCoeff, Start/Mid/Max KI & KP)
  - `Addr12Block` (LD, AlarmDelay, PolePairs, MaxSpeed, RatedPower, RatedVoltage)
  - `Addr18Block` (RatedSpeed, MaxLineCurr, FollowConfig, ThrottleResponse, WeakA, RXD, GearConfig, LQ, BattRatedCap, IntRes)
  - `Addr1EBlock` (FwReRatio, LowVolProtect, CustomCode, RelayDelay, PEnable, SeatEnable, CruiseEnable, EABSEnable, Datum/Uhrzeit)
  - `Addr24Block` (HighVolProtect, CustomMaxLineCurr/Boost, CustomMaxPhaseCurr/Boost, BackSpeed, LowSpeed)
  - `Addr2ABlock` (MidSpeed, Max_Dec, FreeThrottle, MaxPhaseCurr, SpeedAnalog, Max_Acc)
  - `Addr30Block` (StopBackCurr, MaxBackCurr, Low/Mid Speed Line/Phase Current Ratios, BlockTime, SpdPulseNum)
  - `Addr63Block` (MaxLineCurr2, MaxPhaseCurr2, TempCoeff, ProdMaxVol, ISMax)
  - `Addr69Block` (Pin-Belegungen: Pause, SideStand, Cruise, Boost, LowSpeed, HighSpeed, Reverse, Forward, SwitchVol, Seat, AntiTheft, Charge, LmtSpeed)
  - `Addr7CBlock` (WeakTime, QuickDown, SpeedMeterConfig, FastRE, DeepWeak, ZeroSwitch, MOE, Betriebsstunden)
  - `Addr82Block` (ThrottleVoltage, HighVolRestore, Motor/Mos TempProtect & Restore, CANConfig, Versions)
  - `Addr88Block` (Drehzahl-Kurve Teil 1: RatioMin, 500..5500 RPM)
  - `Addr8EBlock` (Drehzahl-Kurve Teil 2: 6000..9000 RPM & Max; Rekuperations-Kurve nratio 0..3)
  - `Addr94Block` (Rekuperations-Kurve Teil 2: nratio 4..15)
  - `Addr9ABlock` (Rekuperations-Kurve Teil 3: nratio 16..19; AN, LM, Stage1Curr, VolSelectRatio)
  - `AddrA0Block` / `AddrA6Block` (Modellname, Seriennummer, Systemkommandos)
  - `AddrB2Block` / `AddrB8Block` (OneComm SEC0..7, Positionen P/BC/Hbar/FD, CANBaud, GPara0)
  - `AddrBEBlock` (LowVolWay, AccCoeff, BoostTime, BoostRelease, ParkTime, ReverseTime, TorqueCoeff)
  - `AddrC4Block` (TapForward/Back, DualThrottleVol, SlowDownRpm, StartIs, ThrottleInsert, ExitFollowSpeed, ReCurrRatio, LearnVol)
  - `AddrCABlock` (AngleLearn, SpeedLimitPin, RepairPin, NoCanCnt, SPModeConfig, Temp70, LongBack, LearnThrottle, BattSignal)
  - `AddrD0Block` (OneComm Data0/1, AVGPower, WheelRatio, WheelRadius, AVGSpeed, WheelWidth, RateRatio, Idle/Stop, SpecialFrame)
  - Statusblöcke: `AddrD6Block`, `AddrDCBlock`, `AddrE2Block`, `AddrE8Block`, `AddrEEBlock`, `AddrF4Block`, `AddrFABlock`
- Erstelle aggregiertes `FarDriverFullMemory`-Objekt mit 512-Byte-Repräsentation und Export/Import.

---

## T014 - Telemetrie-, Fehler- und Safety-Register decodieren
**Status:** [x] Abgeschlossen  
**Referenz:** [`lib/utils/packet_parser.dart`](../lib/utils/packet_parser.dart)

---

## T015 - Parameter-Snapshots aus dem Datenstrom aufbauen
**Status:** [x] Abgeschlossen  
**Referenz:** [`lib/services/snapshot_builder.dart`](../lib/services/snapshot_builder.dart)

---

## T016 - Schreibprotokoll, ACK und HEB validieren
**Status:** [x] Abgeschlossen / Erweitert  
**Referenz:** [`lib/services/protocol_service.dart`](../lib/services/protocol_service.dart), [`lib/services/heb_file_parser.dart`](../lib/services/heb_file_parser.dart)

### Arbeitsumfang
- Unterstützung für:
  - 8-Byte Einzelwort-Writes (`0xAA 0x46 ...`)
  - Block-Writes (`0xAA [0xC0+len] ...`)
  - Bulk-Writes (`0xAA 0xFE ...`)
  - CAN-Writes (`0xAA 0xFF ...`)
  - System-Kommandos (`0xA0 / 0x88 0x05 / 0x08 / 0x01 / 0x02`)
