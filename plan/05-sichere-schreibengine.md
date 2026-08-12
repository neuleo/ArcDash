# Phase 4: Parameterkatalog & Sichere Schreibengine

## Phasenziel

Jede Parameterveränderung — ob einzelner Slider, Profilwechsel, Werks-Restore oder MacroDroid-Trigger — durchläuft dieselbe fehlersichere (fail-closed) Safety- und Transaktionsschicht. Direkte, ungeprüfte Schreibzugriffe auf das BLE-Interface sind ausgeschlossen.

---

## T030 - Umfassenden Parameterkatalog & Hardwaregrenzen definieren

**Referenz:** [`lib/services/write_safety.dart`](../lib/services/write_safety.dart)

### Arbeitsumfang
- Definition von Adresse, Maske, Shift, Rohwert-Grenzen, SI-Grenzen, Einheiten und Risikoklasse für alle 100+ FarDriver-Parameter.
- Unterteilung in 4 Sicherheitsklassen:
  1. `ParameterRisk.comfort`: Unkritisch für Fahrzeugsicherheit (z. B. Display-Einstellungen, Tacho-Impulse).
  2. `ParameterRisk.performance`: Leistungsrelevant (z. B. Max Speed, Line Current, Phase Current, Throttle Response, Regen).
  3. `ParameterRisk.safetyCritical`: Schutzfunktionen & Systemabschaltungen (z. B. Unter-/Überspannung, Temperaturgrenzen, Bremskonfiguration).
  4. `ParameterRisk.hardware`: Hardware- & Sensoreinstellungen (z. B. Polpaare, Pin-Mappings, Phasenverschiebung, ADC-Nullpunkte) — geschützt durch den **Experten-Modus**.

### Tests und Akzeptanz
- Grenzwerte, NaN-Prüfung, Rohwertüberlauf und Masken-Isolation sind vollständig durch Unit-Tests abgedeckt.

---

## T031 - Fail-closed Safety-Evaluator bauen

**Referenz:** [`lib/services/write_safety.dart`](../lib/services/write_safety.dart)

### Arbeitsumfang
- Das Schreiben von Parametern ist nur erlaubt, wenn alle folgenden Bedingungen gleichzeitig erfüllt sind:
  1. BLE-Verbindung aktiv (`connected`).
  2. Fahrzeug steht still (`speedKph == 0.0` und `rpm == 0`).
  3. Telemetriedaten sind aktuell (`maxAge < 1500 ms`).
  4. Keine aktiven Controller-Fehler (`!hasAnyFault`).
  5. Controller-Identität ist bekannt und verifiziert.
  6. Ein funktionierendes Stock-Backup oder Basemap liegt vor.
- Bei jeder Verletzung liefert der Evaluator typisierte Ablehnungsgründe (`SafetyRejection`).

---

## T032 - Read-Modify-Write Engine für Bitfelder und Wort-Updates

**Referenz:** [`lib/services/write_engine.dart`](../lib/services/write_engine.dart)

### Arbeitsumfang
- Vergleicht geänderte Zielwerte mit dem aktuellen Controller-Speicherabbild.
- Berechnet minimale Wort- und Bitfeld-Änderungen (`RawParameterDiff`), ohne benachbarte Bits in Misch-Registern zu zerstören.
- Identische Werte erzeugen 0 Schreiboperationen (Idempotenz).

---

## T033 - Transaktionales Schreiben mit ACK-Prüfung & Read-Back-Verifikation

**Referenz:** [`lib/services/write_engine.dart`](../lib/services/write_engine.dart), [`lib/services/protocol_command_queue.dart`](../lib/services/protocol_command_queue.dart)

### Arbeitsumfang
- Vor jedem Schreibpaket erfolgt eine erneute Stillstands-Prüfung.
- Jedes Paket wird serialisiert über die `ProtocolCommandQueue` gesendet.
- Die Antwort wird auf Übereinstimmung von Adresse und CRC geprüft.
- Nach Abschluss aller Schreibschritte wird der Wert über den rotierenden Telemetrie-Stream zurückgelesen (Read-Back) und in der UI als "Verifiziert" bestätigt.

---

## T034 - Teilfehlerbehandlung & Rollback

### Arbeitsumfang
- Bricht ein Schreibvorgang mitten in einer Sequenz ab (z. B. Verbindungsabbruch oder Safety-Änderung), wird der Zustand sauber erfasst.
- Ein automatischer Rollback auf die Ausgangswerte wird für bereits geschriebene Register ausgeführt, sofern die Verbindung besteht.

---

## T035 - FarDriver Save- & Reboot-Ablauf

### Arbeitsumfang
- Nach dem Schreiben von Konfigurationsblöcken kann bei Bedarf das Persistenz-/Reset-Kommando (`Addr 0xA0 / 0x88 0x05` bzw. `0x08`) ausgelöst werden.
- Die Session fängt den kurzen Verbindungs-Neustart ab und synchronisiert den neuen Parametersatz.
