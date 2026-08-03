# Implementierungsplan: Fullscreen-Dashboard im XE-Pro-R-Stil

## Phase 1: Dashboard-Datenmodell und Layoutvertrag

- [x] 6283833 Task: Dashboard-Modell testgetrieben für frei wählbare Darstellungsarten erweitern
    - [x] Fehlende Model-Tests für die unabhängige Auswahl von Telemetriegröße und Darstellungsart schreiben
    - [x] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [x] Unterstützte Darstellungsarten für Bogen, Balken, Kreis und reine Information modellieren
    - [x] Kompatible Kombinationen aus Telemetriegröße und Darstellung definieren und validieren
    - [x] Mindestgrößen und Größenbeschränkungen pro Darstellungsart festlegen
    - [x] Tests erneut ausführen und den Green-Zustand bestätigen
    - [x] Model-Code refaktorieren und relevante Tests erneut ausführen

- [x] 65cd4db Task: Trip-Distanz und Dashboard-Telemetrie testgetrieben anbinden
    - [x] Tests für Trip-Distanz, fehlende Session-Daten und Datenqualität schreiben
    - [x] Tests für die Aktualisierung der Restreichweite bei geändertem Fahrmodus beziehungsweise Prognosewert schreiben
    - [x] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [x] Trip-Distanz als auswählbare Dashboard-Metrik ergänzen
    - [x] Bestehende Session-Distanz als Datenquelle verwenden
    - [x] Bestehende Reichweitenprognose einschließlich Unsicherheit und Fahrmodusänderungen anbinden
    - [x] Fehlende, veraltete, ungültige und getrennte Daten eindeutig abbilden
    - [x] Tests erneut ausführen und den Green-Zustand bestätigen

- [x] aa5d862 Task: R-inspiriertes Querformat-Standardlayout testgetrieben definieren
    - [x] Tests für das neue Querformat-Standardlayout und das unveränderte unabhängige Hochformatlayout schreiben
    - [x] Prüfen, dass Geschwindigkeit, Leistungsbogen, Akku, Reichweite, Temperaturen, Trip und Modus enthalten sind
    - [x] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [x] Relatives Raster für das R-inspirierte Querformatlayout definieren
    - [x] Zentrale Geschwindigkeit und oberen Leistungsbogen anordnen
    - [x] Pflichtinformationen kompakt im unteren Bereich anordnen
    - [x] Layout validieren und Tests in den Green-Zustand bringen

- [ ] Task: Conductor - Automated Phase Verification 'Phase 1: Dashboard-Datenmodell und Layoutvertrag' (Protocol in workflow.md)

## Phase 2: R-inspiriertes Fahrdisplay

- [ ] Task: Immersive Querformat-Darstellung testgetrieben implementieren
    - [ ] Widget-Tests für Querformat, Fullscreen-Aktivierung und Wiederherstellung der Systemleisten schreiben
    - [ ] Tests für getrenntes Verhalten im Hochformat schreiben
    - [ ] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [ ] Normale App-Navigation im immersiven Fahrmodus ausblenden
    - [ ] Android-Status- und Navigationsleisten im Querformat ausblenden
    - [ ] Systemleisten beim Verlassen des Dashboards oder Wechsel ins Hochformat zuverlässig wiederherstellen
    - [ ] Sichere Möglichkeit zum Verlassen des immersiven Modus erhalten
    - [ ] Tests erneut ausführen und den Green-Zustand bestätigen

- [ ] Task: Zentrale Geschwindigkeitsanzeige und Leistungsbogen testgetrieben gestalten
    - [ ] Golden- oder Widget-Tests für Informationshierarchie, Beschriftungen und Telemetriezustände schreiben
    - [ ] Tests für positive Leistung, Rekuperation und nicht verfügbare Werte schreiben
    - [ ] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [ ] Große zentrale Geschwindigkeitsanzeige mit dynamischer Einheit implementieren
    - [ ] Breiten R-typischen Bogen mit Skala, Live-Wert und Einheit implementieren
    - [ ] Abgestufte Farben für positive Leistung implementieren
    - [ ] Grünen, textlich gekennzeichneten Rekuperationszustand implementieren
    - [ ] Fehlende oder unzuverlässige Werte ohne plausible Ersatzwerte darstellen
    - [ ] Tests erneut ausführen und den Green-Zustand bestätigen

- [ ] Task: Untere Informationszone testgetrieben implementieren
    - [ ] Widget-Tests für Akku, SOC, Reichweite, Unsicherheit, Temperaturen, Trip und Modus schreiben
    - [ ] Tests für lange Profilnamen sowie Warn- und Fehlerzustände schreiben
    - [ ] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [ ] Akkusymbol mit SOC-Prozent implementieren
    - [ ] Modusabhängige Restreichweite mit Unsicherheit darstellen
    - [ ] Motor- und Controller-Temperatur eindeutig beschriften
    - [ ] Trip-Distanz und aktiven Fahrmodus darstellen
    - [ ] Grün-, Amber- und Rot-Zustände mit zusätzlicher textlicher oder ikonografischer Kennzeichnung umsetzen
    - [ ] Tests erneut ausführen und den Green-Zustand bestätigen

- [ ] Task: Conductor - Automated Phase Verification 'Phase 2: R-inspiriertes Fahrdisplay' (Protocol in workflow.md)

## Phase 3: Widget-ähnlicher Dashboard-Editor

- [ ] Task: Expliziten Editiermodus testgetrieben implementieren
    - [ ] Widget-Tests für Bearbeitungsstift, Editorstatus und gesperrten Fahrmodus schreiben
    - [ ] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [ ] Bearbeitungsstift in einer oberen Ecke integrieren
    - [ ] Klar erkennbaren Editiermodus mit Speichern beziehungsweise Beenden umsetzen
    - [ ] Sämtliche Layoutgesten außerhalb des Editiermodus blockieren
    - [ ] Ausreichend große Touch-Flächen und semantische Beschriftungen ergänzen
    - [ ] Tests erneut ausführen und den Green-Zustand bestätigen

- [ ] Task: Drag-and-drop und zweidimensionale Größenänderung testgetrieben implementieren
    - [ ] Tests für Verschieben, horizontales Skalieren und vertikales Skalieren schreiben
    - [ ] Tests für Rastergrenzen, Kollisionen, Mindestgrößen und Abbruch ungültiger Änderungen schreiben
    - [ ] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [ ] Drag-and-drop mit Einrasten im relativen Raster implementieren
    - [ ] Sichtbare Ziehpunkte für Breite und Höhe implementieren
    - [ ] Live-Vorschau der Zielposition und Zielgröße anzeigen
    - [ ] Überlappungen, Bildschirmüberschreitungen und unzulässige Größen verhindern
    - [ ] Touch-Interaktion an Android-Widgets anlehnen
    - [ ] Tests erneut ausführen und den Green-Zustand bestätigen

- [ ] Task: Datenquelle und Darstellungsart testgetrieben konfigurierbar machen
    - [ ] Widget-Tests für das Antippen eines Elements und Öffnen seiner Konfiguration schreiben
    - [ ] Tests für Telemetrieauswahl und kompatible Darstellungsarten schreiben
    - [ ] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [ ] Element-Konfiguration als für Querformat geeigneten Dialog oder Bottom-Sheet implementieren
    - [ ] Wechsel der Telemetriegröße ermöglichen
    - [ ] Wechsel zwischen Bogen, Balken, Kreis und reiner Information ermöglichen
    - [ ] Nicht kompatible Kombinationen ausblenden oder deaktivieren
    - [ ] Änderungen unmittelbar in der Dashboard-Vorschau darstellen
    - [ ] Tests erneut ausführen und den Green-Zustand bestätigen

- [ ] Task: Conductor - Automated Phase Verification 'Phase 3: Widget-ähnlicher Dashboard-Editor' (Protocol in workflow.md)

## Phase 4: Persistenz, Migration und Qualitätsabsicherung

- [ ] Task: Layout-Persistenz und Schema-Migration testgetrieben erweitern
    - [ ] Repository-Tests für das erweiterte Layoutschema schreiben
    - [ ] Tests für bestehende Schema-Versionen, beschädigte Daten und unbekannte Darstellungsarten schreiben
    - [ ] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [ ] Dashboard-Schema versionieren und bestehende gültige Layouts migrieren
    - [ ] Nicht migrierbare Layouts kontrolliert auf ein gültiges Standardlayout zurücksetzen
    - [ ] Änderungen getrennt nach Hoch- und Querformat automatisch speichern
    - [ ] Zurücksetzen auf das R-inspirierte Querformat-Standardlayout ermöglichen
    - [ ] Tests erneut ausführen und den Green-Zustand bestätigen

- [ ] Task: Responsive Darstellung und Barrierefreiheit testgetrieben absichern
    - [ ] Widget-Tests für mehrere typische Querformatgrößen und Seitenverhältnisse schreiben
    - [ ] Tests mit Textskalierung, Displayausschnitten und langen Beschriftungen schreiben
    - [ ] Semantik-Tests für Werte, Warnzustände und Editoraktionen schreiben
    - [ ] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [ ] Größen, Abstände und Typografie responsiv begrenzen
    - [ ] Sichere Randbereiche und Systemgesten berücksichtigen
    - [ ] Überläufe und abgeschnittene Pflichtinformationen verhindern
    - [ ] Semantische Beschriftungen und nicht ausschließlich farbliche Zustandskennzeichnung ergänzen
    - [ ] Tests erneut ausführen und den Green-Zustand bestätigen

- [ ] Task: Dashboard-Gesamtintegration und Regressionen prüfen
    - [ ] Integrations- beziehungsweise Widget-Flow für Anzeigen, Bearbeiten, Speichern und erneutes Laden ergänzen
    - [ ] Vollständige Testsuite mit `docker compose run --rm flutter flutter test` ausführen
    - [ ] Coverage mit `docker compose run --rm flutter flutter test --coverage` erzeugen
    - [ ] Für neuen Code eine Testabdeckung von mehr als 80 Prozent prüfen
    - [ ] Statische Analyse mit `docker compose run --rm flutter flutter analyze --no-fatal-infos` ausführen
    - [ ] Formatierung mit `docker compose run --rm flutter dart format --set-exit-if-changed lib test` prüfen
    - [ ] Android-Build mit `docker compose run --rm flutter flutter build apk` verifizieren
    - [ ] Abweichungen dokumentieren und gefundene Regressionen beheben

- [ ] Task: Manuelle Dashboard-Verifikation vorbereiten
    - [ ] Prüfschritte für ein Android-Gerät im Querformat dokumentieren
    - [ ] Fullscreen-Eintritt und zuverlässige Wiederherstellung der Systemleisten prüfen
    - [ ] Ablesbarkeit, Telemetrieaktualisierung und Rekuperationszustand während einer simulierten Fahrt prüfen
    - [ ] Editor mit Touch, Drag-and-drop und Größenänderung prüfen
    - [ ] Persistenz nach App-Neustart und Orientierungswechsel prüfen
    - [ ] Verhalten bei BLE-Trennung und veralteten Daten prüfen

- [ ] Task: Conductor - Automated Phase Verification 'Phase 4: Persistenz, Migration und Qualitätsabsicherung' (Protocol in workflow.md)
