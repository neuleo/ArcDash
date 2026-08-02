# Tech Stack

## Platform & Framework

- **Dart 3.12.0** (SDK constraint `>=3.10.3 <4.0.0` from `pubspec.lock`) — primary programming language.
- **Flutter 3.44.0** (`ghcr.io/cirruslabs/flutter:stable@sha256:46691e311715845de03a3ba4753a475476936805b29431b1f00f1816981033f8`) — UI framework. **Primär Android** (iOS nur Nice-to-have); weitere Desktop-Targets (macOS, Windows, Linux) vorhanden, aber sekundär.

## State Management

- **flutter_riverpod** — reactive state management.

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
- Provider werden bewusst ohne Codegen und Annotationen implementiert.

## Build & Test Environment

All build processes, tests, and linting run **exclusively inside Docker containers**. No local Dart/Flutter dependencies are installed on the host.

- **Dockerfile** — base image `ghcr.io/cirruslabs/flutter:stable` (includes Flutter SDK, Android SDK, Java). Disables analytics and treats the mounted repo as a trusted git worktree.
- **docker-compose.yml** — single `flutter` service mounting the project into `/app`, with persistent volumes for the Dart package cache (`flutter_pub_cache`) and the Gradle cache (`gradle_cache`).
- **Makefile** — convenience targets that wrap `docker compose run --rm flutter ...`.

The toolchain is intentionally pinned to the image digest above. To update it,
run `docker compose build --pull`, record the new digest and the output of
`flutter --version`, `dart --version`, `java -version` and
`flutter doctor -v` in `plan/baseline.md`, then run `flutter pub get` twice and
confirm that `pubspec.lock` is unchanged. To rebuild caches, remove only the
named `flutter_pub_cache` and `gradle_cache` Docker volumes before rebuilding;
never delete project source or lockfiles.

Standard commands:

```bash
docker compose build                                    # build the image
docker compose run --rm flutter flutter pub get         # install dependencies
# No code generation is currently used; providers are explicit Dart values.
docker compose run --rm flutter flutter analyze --no-fatal-infos # lint / static analysis
docker compose run --rm flutter flutter test            # run tests
docker compose run --rm flutter flutter test --coverage # coverage report
docker compose run --rm flutter flutter build apk       # build Android APK
docker compose run --rm flutter flutter build linux     # build Linux desktop
```

Equivalent Make targets: `make build`, `make pub-get`, `make analyze`, `make test`, `make coverage`, `make build-apk`, `make build-linux`, `make check`.

## Architecture

Single Flutter application (fork of Biketunes) with a strict separation: **BLE/Protocol Layer ↔ State Management ↔ UI**.

- `lib/models/` — domain models (controller state, ride stats, tuning profiles).
- `lib/providers/` — Riverpod providers (Bluetooth, controller state, tuning, stats).
- `lib/services/` — services (Bluetooth, FarDriver protocol, storage, background/profile).
- `lib/screens/` — UI screens (connection, dashboard, tuning, stats, debug, settings).
- `lib/widgets/` — reusable widgets (gauges, indicators, tiles, cards).
- `lib/utils/` — helpers (CRC calculator, packet parser, unit converter).

Bestehendes Protokoll-Handling, BLE-Kommunikation, Parameter-Schreiben und Backup-System von Biketunes werden als Fundament wiederverwendet und nur abgesichert/erweitert.
