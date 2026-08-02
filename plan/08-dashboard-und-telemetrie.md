# Phase 7: Dashboard und Telemetrie

## Phasenziel

Das sichtbare ArcDash-Cockpit ist deutsch, AMOLED-optimiert, bei Sonne lesbar
und mit Handschuhen bedienbar. Es zeigt ausschliesslich plausible und hinsichtlich
ihrer Aktualitaet bewertete Telemetrie.

## T054 - Designsystem, Navigation und Lokalisierung aufbauen

**Abhaengigkeiten:** T006, T008  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Definiere AMOLED-Farben, Typografie, Abstaende, Touch-Ziele und Safety-Farben
  gemaess `conductor/product-guidelines.md`.
- Bette Fonts lokal ein oder verwende Systemfonts ohne Laufzeit-Netzwerkzugriff.
- Richte Flutter-Lokalisierung mit Deutsch als Standard und Englisch als
  optionaler Sprache ein.
- Vereinfache Navigation auf Dashboard, Profile, Fahrten und Einstellungen.

### Tests und Akzeptanz

- Kein zentraler Nutzertext ist hart im Widget verdrahtet.
- App startet offline ohne Font-Download.
- Touch-Ziele sind mindestens 48 dp und Textskalierung verursacht keinen
  kritischen Overflow.
- Theme- und Navigations-Smoke-Tests bestehen.

## T055 - Telemetriequalitaet und Stale-State implementieren

**Abhaengigkeiten:** T014, T018  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Fuehre pro Messwert Quelle, Erfassungszeit, Gueltigkeit und optional geglaetteten
  Anzeigewert.
- Definiere physikalische Plausibilitaetsgrenzen und unterschiedliche
  Stale-Zeitfenster fuer schnelle und langsame Frames.
- Verhindere, dass alte Werte nach Disconnect wie live aussehen.

### Tests und Akzeptanz

- Fake-Clock-Tests decken frisch, stale, ungueltig und reconnect ab.
- Glattung erzeugt keine gefaehrliche lange Verzogerung fuer Fehler oder RPM.
- Rohwerte bleiben fuer Diagnose verfuegbar.

## T056 - GPS-Geschwindigkeit mit Fallback implementieren

**Abhaengigkeiten:** T019, T055; neue Abhaengigkeit vorab im Tech Stack  
**Hardware erforderlich:** Android-Geraet fuer Abnahme

### Arbeitsumfang

- Fuehre Location-Permissions getrennt von BLE-Rechten und erklaere den Nutzen.
- Filtere GPS nach Accuracy, Alter und realistischer Beschleunigung.
- Bevorzuge gueltiges GPS; falle bei schlechter Qualitaet auf Controller-Speed
  zurueck und kennzeichne die Quelle intern.
- Behandle Stillstand stabil, ohne GPS-Drift als Fahrt zu zaehlen.

### Tests und Akzeptanz

- Quellenauswahl, stale GPS, Spruenge, Drift und Permission-Ablehnung sind
  deterministisch getestet.
- Dashboard zeigt auch ohne Standortfreigabe Controller-Speed.
- Hintergrundstandort wird nur angefordert, wenn spaetere Sessionanforderungen
  dies technisch und rechtlich rechtfertigen.

## T057 - AMOLED-Dashboard und Leistungsbogen bauen

**Abhaengigkeiten:** T054 bis T056  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Baue eine grosse Geschwindigkeitsanzeige und einen halbkreis-/bogenfoermigen
  Leistungsindikator fuer aktuelle kW.
- Faerbe positive Leistung gestuft und negative Leistung/Rekuperation gruen.
- Zeige Spannung, Strom, SOC und Reichweite in klarer visueller Hierarchie.
- Vermeide kleine Kartenraster und dekorative Effekte, die Sonnenlesbarkeit
  verschlechtern.

### Tests und Akzeptanz

- Widget-/Golden-Tests decken idle, Leistung, Rekuperation, stale und Fehler ab.
- Layout funktioniert auf den definierten kleinen und grossen Zielgeraeten.
- Wichtige Werte sind ohne Scrollen sichtbar.

## T058 - Profil, DNR, Temperaturen und Fehler darstellen

**Abhaengigkeiten:** T044, T055, T057  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Zeige aktives/verifiziertes/abweichendes Profil, D/N/R beziehungsweise Gang,
  Motor- und Controllertemperatur sowie kompakte Fehlerindikatoren.
- Nutze gruen, amber und rot konsistent mit realen Schwellen und Schutzflags.
- Biete vom Dashboard einen schnellen, aber weiterhin bestaetigten Profilzugang.

### Tests und Akzeptanz

- Unbekannter Gang oder Temperaturwert wird als unbekannt, nicht als Null gezeigt.
- Temperaturwarnungen basieren auf konfigurierten/bestaetigten Grenzen.
- Profilstatus kann nicht mit Controller-Verifikationsstatus verwechselt werden.

## T059 - Einheiten und Accessibility umsetzen

**Abhaengigkeiten:** T054, T057, T058  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Verbinde km/h/mph und km/mi konsistent mit allen Dashboard-, Session- und
  Exportansichten; interne Berechnung bleibt SI.
- Ergaenze Semantics, Kontrastpruefung, grosse Textskalierung und ausreichend
  grosse Handschuh-Touchziele.
- Stelle Informationen nie ausschliesslich durch Farbe dar.

### Tests und Akzeptanz

- Umrechnung und Rundung besitzen Unit-Tests.
- Accessibility-Tests finden Labels fuer zentrale Werte und Aktionen.
- 200 Prozent Textskalierung bleibt fuer kritische Flows nutzbar.

## T060 - Verbindungs-UX vereinheitlichen

**Abhaengigkeiten:** T021, T054  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Entferne doppelte/umgangene Connection-Flows und schaffe einen eindeutigen
  Einstieg fuer Erstverbindung, Reconnect und Geraetewechsel.
- Zeige Adapter, Permission, Scan, Connect, Reconnect und Fehler getrennt.
- Verhindere, dass ein Dashboard mit Defaultnullen wie verbunden wirkt.

### Tests und Akzeptanz

- Widgettests decken Erststart, verweigerte Permission, kein Geraet, Connect,
  Disconnect und Reconnect ab.
- Navigation verliert den Sessionzustand nicht.
- Manuelles Trennen beendet gewollten Auto-Reconnect.

## Phasen-Gate

Alle in Version 1 geforderten Livewerte sind mit Quelle und Aktualitaet
dargestellt. Das Cockpit besteht Layout-, Kontrast- und Handschuhbedienungschecks.
