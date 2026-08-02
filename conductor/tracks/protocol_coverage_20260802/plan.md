# Implementation Plan: FarDriver Protocol Layer Test Coverage

> Track: `protocol_coverage_20260802`
> Spec: [./spec.md](./spec.md)

All commands run inside the Docker container (`make test`, `make codegen`, etc.). Follow the TDD lifecycle from `conductor/workflow.md` (Red → Green → Refactor), commit after every task, attach a git note with the task summary, and update the task status in this file with the commit SHA prefix.

---

## Phase 1: Test Infrastructure Setup

- [ ] Task: Set up protocol-layer test infrastructure
    - [ ] Create `test/utils/` and `test/services/` directories with mirrored test files for `crc_calculator.dart`, `packet_parser.dart`, `protocol_service.dart`, and `unit_converter.dart`
    - [ ] Add shared test helpers (e.g., known-good packet builders / reference vectors) in `test/helpers/`
    - [ ] Verify the suite runs inside Docker via `make test`
- [ ] Task: Conductor - User Manual Verification 'Test Infrastructure Setup' (Protocol in workflow.md)

## Phase 2: CRC Calculator Tests

- [ ] Task: Unit tests for CRC calculation and verification
    - [ ] Write failing tests for `CrcCalculator.computeCRC` and `CrcCalculator.verifyCRC` against known-good reference vectors (start values a=0x3C, b=0x7F) from the FarDriver protocol reference
    - [ ] Implement/fix `CrcCalculator` to make the tests pass (Green phase)
    - [ ] Run `make test` and confirm all CRC tests pass
- [ ] Task: Conductor - User Manual Verification 'CRC Calculator Tests' (Protocol in workflow.md)

## Phase 3: Packet Building Tests (ProtocolService)

- [ ] Task: Unit tests for packet building and system commands
    - [ ] Write failing tests for `buildWritePacket`, `buildWritePacket16`, `buildSysCmd`, `setMaxLineCurrPacket`, `setMaxSpeedPacket`, `setThrottleResponsePacket`, `kphToMaxSpeedRaw`, and `verifyWriteAck`, covering normal, boundary, and invalid inputs
    - [ ] Implement/fix `ProtocolService` to make the tests pass (Green phase)
    - [ ] Run `make test` and confirm all packet-building tests pass
- [ ] Task: Conductor - User Manual Verification 'Packet Building Tests' (Protocol in workflow.md)

## Phase 4: Packet Parsing Tests (PacketParser)

- [ ] Task: Unit tests for packet extraction and status parsing
    - [ ] Write failing tests for `extractPackets` (16-byte status + 8-byte write ack, CRC rejection, stream offset handling), `parseStatusPacket`, `readInt16LE`, `readUint16LE`, `readPhaseCurrent`, `toHexString`, and the `flashReadAddr` id mapping (id < 0x37)
    - [ ] Implement/fix `PacketParser` to make the tests pass (Green phase)
    - [ ] Run `make test` and confirm all parsing tests pass
- [ ] Task: Conductor - User Manual Verification 'Packet Parsing Tests' (Protocol in workflow.md)

## Phase 5: Telemetry Decoding Tests

- [ ] Task: Unit tests for telemetry extraction and unit conversion
    - [ ] Write failing tests for `extractTelemetry` for every supported address (0xE2 speed/status, 0xE8 voltage/current, 0xEE phase currents, 0xF4 motor temp/SOC, 0xD6 MOSFET temp, 0xD0 wheel geometry, 0x12 max speed, 0x18 max line current, 0x0C battery calibration) and for unknown addresses returning null
    - [ ] Write failing tests for `UnitConverter` (kph/mph, temperature, `measureSpeedToKph`, `powerKw`, `batteryPercent`, `estimatedRangeKm`, formatting)
    - [ ] Implement/fix `PacketParser`/`UnitConverter` to make the tests pass (Green phase)
    - [ ] Run `make test` and confirm all telemetry tests pass
- [ ] Task: Conductor - User Manual Verification 'Telemetry Decoding Tests' (Protocol in workflow.md)

## Phase 6: Coverage Verification & Documentation

- [ ] Task: Verify coverage gate and finalize documentation
    - [ ] Run `make coverage` and confirm protocol-layer coverage exceeds 80%; add missing tests for any uncovered branches
    - [ ] Run `flutter analyze` inside the container and fix all lint/analysis issues
    - [ ] Run `dart format --set-exit-if-changed lib test` inside the container
    - [ ] Update `conductor/product.md`, `conductor/tech-stack.md`, or `conductor/workflow.md` if this track revealed any deviations
- [ ] Task: Conductor - User Manual Verification 'Coverage Verification & Documentation' (Protocol in workflow.md)
