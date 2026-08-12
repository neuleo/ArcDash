# FarDriver Protokoll-Belegmatrix (Vollständige Snapshot-Abdeckung)

Geltungsbereich: [`reference/controller_snapshot.md`](../reference/controller_snapshot.md), [`reference/upstream/fardriver-controllers/fardriver.hpp`](../reference/upstream/fardriver-controllers/fardriver.hpp), [`reference/upstream/fardriver-controllers/HEB.bt`](../reference/upstream/fardriver-controllers/HEB.bt) und ArcDash Speichermodell.

## Statusbegriffe

- **BESTAETIGT**: Lückenlos im Upstream-C++-Header (`fardriver.hpp`), im Binary Template (`fardriver.bt` / `HEB.bt`) und durch Snapshot-Daten (`controller_snapshot.md`) belegt.
- **SCHREIBBAR**: Über 8-Byte-Einzelwort-Schreibbefehl (`0xAA 0x46 ...`), Block-Schreibbefehl (`0xAA 0xCC ...`) oder Bulk-Schreibbefehl (`0xAA 0xFE ...`) modifizierbar.
- **EXPERT**: Hardwarekritischer Parameter, erfordert Bestätigung im Experten-Modus.

---

## 1. Übersicht der 26 FarDriver Speicherblöcke (je 12 Bytes = 312 Bytes Parameter + 384 Bytes CAN = 696 Bytes HEB)

| Block-Adresse | Enthaltene Hauptparameter | Schreibbar | Risikoklasse |
|---:|---|:---:|---|
| `0x00` | Kalibrierung: VolCoeff, PhaseACoeff, LineCoeff, PhaseCCoeff, SaveNum | Ja (Expert) | Hardware / Kalibrierung |
| `0x06` | MorseCode, SpeedKI/KP, ThrottleLow/High, FAIF, CurveTime, BrakeConfig, TempSensor, PhaseExchange, Direction | Ja | Comfort & Safety |
| `0x0C` | PhaseOffset, ZeroBattCoeff, FullBattCoeff, StartKI/KP, MidKI/KP, MaxKI/KP | Ja | Safety & Performance |
| `0x12` | LD (Induktanz), AlarmDelay, PolePairs, MaxSpeed, RatedPower, RatedVoltage | Ja | Performance & Hardware |
| `0x18` | RatedSpeed, MaxLineCurr, FollowConfig, ThrottleResponse, WeakA, RXD, SpeedPulse, GearConfig, LQ, BattRatedCap, IntRes | Ja | Daily Tuning & Safety |
| `0x1E` | FwReRatio, LowVolProtect, CustomCode, RelayDelay, PEnable, SeatEnable, CruiseEnable, EABSEnable, Datum/Uhrzeit | Ja | Safety & Features |
| `0x24` | HighVolProtect, CustomMaxLineCurr (Boost), CustomMaxPhaseCurr (Boost), BackSpeed, LowSpeed | Ja | Performance & Safety |
| `0x2A` | MidSpeed, Max_Dec, FreeThrottle, MaxPhaseCurr, SpeedAnalog, Max_Acc | Ja | Daily Tuning & Performance |
| `0x30` | StopBackCurr, MaxBackCurr, LowSpeedLineCurr, MidSpeedLineCurr, LowSpeedPhaseCurr, MidSpeedPhaseCurr, BlockTime, SpdPulseNum | Ja | Regen & Gear Ratios |
| `0x63` | MaxLineCurr2, MaxPhaseCurr2, TempCoeff, ProdMaxVol, ISMax | Ja (Expert) | Hardware Limits |
| `0x69` | Pin-Belegungen: Pause, SideStand, Cruise, Boost, LowSpeed, HighSpeed, Reverse, Forward, SwitchVol, Seat, AntiTheft, Charge, LmtSpeed, Mileage | Ja | Pin Configuration |
| `0x7C` | WeakTime, QuickDown, SpeedMeterConfig, FastRE, DeepWeak, ZeroSwitch, MOE, Betriebsstunden, Distanz | Ja | Features & PID |
| `0x82` | ThrottleVoltage, HighVolRestore, MotorTempProtect/Restore, MosTempProtect/Restore, CANConfig, HW/SW Version | Ja | Safety Cutoffs |
| `0x88` | Drehzahl-Kurve Teil 1: RatioMin, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000, 5500 RPM | Ja | Performance Curves |
| `0x8E` | Drehzahl-Kurve Teil 2: 6000, 6500, 7000, 7500, 8000, 8500, 9000 RPM, RatioMax; Rekuperation nratio 0..3 | Ja | Performance & Regen Curves |
| `0x94` | Rekuperation Teil 2: nratio 4..15 (Drehzahl-abhängige Bremsströme) | Ja | Regen Curves |
| `0x9A` | Rekuperation Teil 3: nratio 16..19, AN (Wave Type), LM (Wave Interval), Stage1Curr, VolSelectRatio | Ja | Regen & PID |
| `0xA0` | Systemkommandos (Save, Reset, SelfLearn) & Modell-Typname Teil 1 (10 Chars) | Ja | System / Identity |
| `0xA6` | Modell-Typname Teil 2 (10 Chars) & Controller-Seriennummer | Ja (Read-only) | Identity |
| `0xAC` | Erweiterte PIN-/Passwort-Register | Ja (Expert) | Security |
| `0xB2` | OneComm Sec 0..7 (Display-Protokoll-Konfiguration) | Ja | Display |
| `0xB8` | Display Positionen (P, BC, Hbar, FD), Pulse, SQH, OnelineCurrCoeff, BackPTime, ReleaseToSeat, CANBaud | Ja | Display & CAN |
| `0xBE` | LowVolWay, AccCoeff, BoostTime, BoostRelease, ParkTime, ReverseTime, TorqueCoeff | Ja | Performance & Display |
| `0xC4` | TapForward/Back, DualThrottleVol, SlowDownRpm, StartIs, ThrottleInsert, ExitFollowSpeed, ReCurrRatio, LearnVol | Ja | Advanced Tuning |
| `0xCA` | AngleLearn, SpeedLimitPin, RepairPin, NoCanCnt, SPModeConfig, Temp70, LongBack, LearnThrottle, BattSignal | Ja | Pins & Modes |
| `0xD0` | OneComm Data0/Data1, AVGPower, WheelRatio, WheelRadius, AVGSpeed, WheelWidth, RateRatio, Idle/Stop, SpecialFrame | Ja | Tacho & Display |

---

## 2. Detaillierte Feldbelegung nach Snapshot-Kategorien

### 1. General Info & DateTime
- `ModelType`: Addr `0xA0` (Bytes 2..11) + Addr `0xA6` (Bytes 0..9) (ASCII String, z. B. `BJ72V250AB_27_1KMA66`)
- `Voltage/Power`: `RatedVoltage` @ `0x12` + `RatedPower` @ `0x12`
- `LineCurr/PhaseCurr`: `MaxLineCurr` @ `0x18` (180 A) + `MaxPhaseCurr` @ `0x2A` (450 A)
- `ProductCode`: Addr `0xA6` (ASCII)
- `CostumCode`: Addr `0x1E` (Bytes 4..5, z. B. `BJ`)
- `MorseCode`: Addr `0x06` (Bits 0..6)
- `Date & Time`: Addr `0x1E` (ModelYear, Month, Day, Hour), Addr `0x24` (Minute, Second)

### 2. Parameters (Motor & Fahrverhalten)
- `AngleDetect`: Addr `0xD0` (BMQHALL) & Addr `0xCA` (AngleLearn)
- `TempSensor`: Addr `0x06` (Bits 4..6 in Byte 10: 0=None, 1=PTC, 2=NTC230K, 3=KTY84_130, 4=CACU, 5=KTY83_122, 6=NTC10K, 7=NTC100K)
- `PhaseOffset`: Addr `0x0C` (int16_t, Skalierung / 10.0 Grad)
- `PolePairs`: Addr `0x12` (uint8_t)
- `Motor Direction`: Addr `0x06` (Bit 7 in Byte 11)
- `RatedSpeed`: Addr `0x18` (uint16_t, RPM)
- `RatedVoltage`: Addr `0x12` (uint16_t, / 10.0 V)
- `RatedPower`: Addr `0x12` (uint16_t, W)
- `MaxSpeed`: Addr `0x12` / Write `0x15` (uint16_t, RPM)
- `BackSpeed`: Addr `0x24` (uint16_t, RPM)
- `MaxLineCurr`: Addr `0x18` / Write `0x19` (uint16_t, / 4.0 A)
- `MaxPhaseCurr`: Addr `0x2A` / Write `0x1A` (uint16_t, / 4.0 A)
- `ThrottleResponse`: Addr `0x18` (Bits 2..3: 0=Line, 1=Sport, 2=ECO)
- `Throttle Acc Step` / `Max_Acc`: Addr `0x2A` (uint16_t)
- `Throttle Dec Step` / `Max_Dec`: Addr `0x2A` (uint16_t)
- `BoostLineCurr`: Addr `0x24` (CustomMaxLineCurr, uint16_t / 4.0 A)
- `BoostPhaseCurr`: Addr `0x24` (CustomMaxPhaseCurr, uint16_t / 4.0 A)
- `PhaseExchange`: Addr `0x06` (Bit 7 in Byte 10)
- `ECOAccCoeff`: Addr `0xBE` (Bits 4..7)
- `Weak Character`: Addr `0x18` (WeakA Bits 4..5)
- `WeakResponse`: Addr `0x7C` (WeakTime Bits 1..3)
- `Release Throttle`: Addr `0x2A` (FreeThrottle uint8_t)
- `Throttle Low`: Addr `0x06` (uint8_t, / 20.0 V)
- `Throttle High`: Addr `0x06` (uint8_t, / 20.0 V)

### 3. Ratios in Speed (18-Punkte Drehzahlkurve)
- `500RPM .. 5500RPM`: Addr `0x88` (12 Bytes, uint8_t Prozentwerte 0..100%)
- `6000RPM .. 9000RPM & Max`: Addr `0x8E` (8 Bytes, uint8_t Prozentwerte)
- `LD`: Addr `0x12` (int16_t)
- `LQ`: Addr `0x18` (uint16_t)
- `FAIF`: Addr `0x06` (int16_t)
- `LimitSpeed`: Addr `0x69` (uint16_t, RPM)

### 4. Ratios in Gear
- `LowSpeedLineRatio`: Addr `0x30` (uint8_t, `raw * 100 / 128`)
- `MidSpeedLineRatio`: Addr `0x30` (uint8_t)
- `LowSpeedPhaseRatio`: Addr `0x30` (uint8_t)
- `MidSpeedPhaseRatio`: Addr `0x30` (uint8_t)
- `LowSpeed`: Addr `0x24` (uint16_t, RPM)
- `MiddleSpeed`: Addr `0x2A` (uint16_t, RPM)

### 5. Energy Regenerate
- `StopBackCurr`: Addr `0x30` (uint16_t A)
- `MaxBackCurr`: Addr `0x30` (uint16_t A)
- `Batt RatedCapacity`: Addr `0x18` (uint16_t Ah)
- `FreeThrottle`: Addr `0x2A` (uint8_t)
- `Brake Voltage`: Addr `0x82` (ThrottleVoltage uint16_t * 0.01 V)
- `500RPM .. 9000RPM Regen`: Addr `0x8E` (Bytes 8..11), Addr `0x94` (Bytes 0..11), Addr `0x9A` (Bytes 0..3) (int8_t negativer Prozentsatz)

### 6. Functions & Pin-Mapping
- `Pins (0x69, 0xCA)`: 4-Bit Enums für jeden Pin (0=NC, 1=PIN24, 2=PIN15, 3=PIN5, 4=PIN17, 5=PIN14, 6=PIN3, 7=PIN8, 8=PB4, 10=PIN2, 11=PIN18, 12=PIN9, 13=PD1, 15=Invalid).
  - Boost Pin, Cruise Pin, SideStand Pin, Pause Pin
  - LowSpeed Pin, HighSpeed Pin, Reverse Pin, Forward Pin
  - SwitchVol Pin, Seat Pin, AntiTheft Pin, Charge Pin
  - SpeedLimit Pin, Repair Pin
- `BoostTime`: Addr `0xBE` (uint16_t / 500 s)
- `BoostRelease`: Addr `0xBE` (uint16_t / 500 s)
- `HighLowSpeed`: Addr `0xCA` (SPModeConfig Enum: 0..14)
- `Gear`: Addr `0x18` (GearConfig Enum: DefaultN=0, DefaultD=1, etc.)
- `Brake`: Addr `0x06` (BrakeConfig Enum: StopWhenGround=0, StopWhenFloat=1, P_StopGnd=2, etc.)
- `PC13`: Addr `0x06` (RaceResponse Bit)
- `Park`: Addr `0x06` (ParkConfig Enum)
- `Follow`: Addr `0x18` (FollowConfig Enum)

### 7. Protect & Cutoffs
- `OverVolProtect`: Addr `0x24` (uint16_t / 10.0 V)
- `OverVolRestore`: Addr `0x82` (uint16_t / 10.0 V)
- `LowVolProtect`: Addr `0x1E` (uint16_t / 10.0 V)
- `MotorTempProtect` / `Restore`: Addr `0x82` (uint8_t °C)
- `ControllerTempProtect` / `Restore`: Addr `0x82` (uint8_t °C)
- `0 BattCoeff` / `Full BattCoeff`: Addr `0x0C` (int16_t)
- `BlockTime`: Addr `0x30` (uint16_t s)
- `ParkTime`: Addr `0xBE` (uint16_t / 500 s)
- `BattSignal`: Addr `0xCA` (Lithium, LeadAcid, LFP, CAN, Serial)
- `LowVol Way`: Addr `0xBE` (Vol2V, Vol4V, Soc5Perc, etc.)
- `IntRes`: Addr `0x18` (uint16_t mOhm)
- `TempCoeff`: Addr `0x63` (uint16_t)

### 8. PID Paras
- `AN`: Addr `0x9A` (Bits 0..3, Wave Type)
- `LM`: Addr `0x9A` (Bits 0..4, Wave Interval)
- `StartKI` / `StartKP`: Addr `0x0C`
- `MidKI` / `MidKP`: Addr `0x0C`
- `MaxKI` / `MaxKP`: Addr `0x0C`
- `SpeedKI` / `SpeedKP`: Addr `0x06`
- `MOE`: Addr `0x7C` (Bit 6)
- `CurveTime`: Addr `0x06` (int16_t ms)
