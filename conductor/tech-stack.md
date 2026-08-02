# Tech Stack

## Platform & Framework

- **Dart** (SDK >= 3.2) — primary programming language.
- **Flutter** — UI framework. **Primär Android** (iOS nur Nice-to-have); weitere Desktop-Targets (macOS, Windows, Linux) vorhanden, aber sekundär.

## State Management

- **flutter_riverpod** — reactive state management.
- **riverpod_annotation** — codegen annotations for providers.
- **riverpod_generator** — provider code generation.
- **build_runner** — code generation runner.

## Bluetooth

- **flutter_blue_plus** — BLE communication with the FarDriver dongle (BLE UART service `0000FFE0-...`, characteristic `0000FFE1-...`).

## Background & Platform Integration

- **Android Foreground Service** (`connectedDevice`-Typ) — stabiler BLE-Hintergrundbetrieb mit persistenter Benachrichtigung.
- **MacroDroid-Integration** — Empfang eines Intents/Deep-Links (Volume-Down-Doppelklick) zum Auslösen von Profilwechseln im Hintergrund, ohne dass der Bildschirm angeht.
- **permission_handler** — runtime permissions (Bluetooth, Standort für BLE-Scan).

## Storage & Persistence

- **shared_preferences** — lightweight key/value settings storage.
- **path_provider** — platform file-system directories (Profil-Export/Import, Backups).
- **JSON** — Profil-Format für Export/Import.

## Telemetry & Range Prediction

- **fl_chart** — Telemetrie-Visualisierungen.
- **Coulomb Counting** — Integration von Spannung × Strom für die Reichweitenprognose.
- **Komplementärfilter** — mit spannungsbasiertem SOC.
- **GPS** — Distanzmessung für gleitendes Verbrauchsfenster (Wh/km).
- **csv** — Datenexport (Session-Statistiken).

## Future Navigation (Version 2+)

- **flutter_map** — Karten-Anzeige (kostenlos, OpenStreetMap-basiert).
- **Kostenlose Routing-Engine** (GraphHopper / Valhalla / OSRM) — keine bezahlten APIs.

## Utilities

- **intl** — Datums-/Zahlenformatierung.
- **google_fonts** — Font-Theming.

## Testing & Linting

- **flutter_test** — Unit-/Widget-Testing.
- **flutter_lints** — default lint rules.
- **custom_lint** + **riverpod_lint** — Riverpod-spezifisches Linting.

## Build & Test Environment

All build processes, tests, code generation, and linting run **exclusively inside Docker containers**. No local Dart/Flutter dependencies are installed on the host.

- **Dockerfile** — base image `ghcr.io/cirruslabs/flutter:stable` (includes Flutter SDK, Android SDK, Java). Disables analytics and treats the mounted repo as a trusted git worktree.
- **docker-compose.yml** — single `flutter` service mounting the project into `/app`, with persistent volumes for the Dart package cache (`flutter_pub_cache`) and the Gradle cache (`gradle_cache`).
- **Makefile** — convenience targets that wrap `docker compose run --rm flutter ...`.

Standard commands:

```bash
docker compose build                                    # build the image
docker compose run --rm flutter flutter pub get         # install dependencies
docker compose run --rm flutter dart run build_runner build --delete-conflicting-outputs
docker compose run --rm flutter flutter analyze         # lint / static analysis
docker compose run --rm flutter flutter test            # run tests
docker compose run --rm flutter flutter test --coverage # coverage report
docker compose run --rm flutter flutter build apk       # build Android APK
docker compose run --rm flutter flutter build linux     # build Linux desktop
```

Equivalent Make targets: `make build`, `make pub-get`, `make codegen`, `make analyze`, `make test`, `make coverage`, `make build-apk`, `make build-linux`, `make check`.

## Architecture

Single Flutter application (fork of Biketunes) with a strict separation: **BLE/Protocol Layer ↔ State Management ↔ UI**.

- `lib/models/` — domain models (controller state, ride stats, tuning profiles).
- `lib/providers/` — Riverpod providers (Bluetooth, controller state, tuning, stats).
- `lib/services/` — services (Bluetooth, FarDriver protocol, storage, background/profile).
- `lib/screens/` — UI screens (connection, dashboard, tuning, stats, debug, settings).
- `lib/widgets/` — reusable widgets (gauges, indicators, tiles, cards).
- `lib/utils/` — helpers (CRC calculator, packet parser, unit converter).

Bestehendes Protokoll-Handling, BLE-Kommunikation, Parameter-Schreiben und Backup-System von Biketunes werden als Fundament wiederverwendet und nur abgesichert/erweitert.
