import 'package:arcdash/models/controller_identity.dart';
import 'package:arcdash/services/write_safety.dart';
import 'package:flutter_test/flutter_test.dart';

const identity = ControllerIdentity(
  model: 'FD72680',
  hardwareVersion: 'HW1',
  firmwareVersion: '1.2.0',
  functionCode: 'F0',
  extensionCode: 'E1',
  bindingId: 'binding-a',
);

SafetySample _sample(DateTime at, {int rpm = 0}) => SafetySample(
      at: at,
      rpm: rpm,
      motorRunning: false,
      directionKnown: true,
      brakeActive: false,
      throttleZero: true,
    );

void main() {
  test('catalog exposes confirmed raw and physical bounds', () {
    final catalog = const ParameterCatalog();

    final speed = catalog['maxSpeed'];
    expect(speed.writable, isTrue);
    expect(speed.minRaw, 10 * 72);
    expect(speed.maxRaw, 130 * 72);
    expect(speed.inPhysicalRange(10), isTrue);
    expect(speed.inPhysicalRange(130), isTrue);
    expect(speed.inPhysicalRange(5), isFalse);
    expect(speed.inPhysicalRange(200), isFalse);

    final current = catalog['maxLineCurrent'];
    expect(current.writable, isTrue);
    expect(current.minRaw, 40);
    expect(current.maxRaw, 1200);
    expect(current.inPhysicalRange(300), isTrue);
    expect(current.inPhysicalRange(310), isFalse);
    expect(current.validateRaw(40 * 4), 160);
    expect(current.validateRaw(1201), isNull);

    final throttle = catalog['throttleResponse'];
    expect(throttle.writable, isTrue);
    expect(throttle.validateRaw(3), 3);
    expect(throttle.validateRaw(4), isNull);
    expect(() => throttle.applyToWord(0xFFF3, 3), returnsNormally);
  });

  test('fails closed on moving, stale telemetry, faults and disconnects', () {
    final now = DateTime.utc(2026, 1, 1);
    final evaluator = const SafetyEvaluator();
    final fresh = now.subtract(const Duration(milliseconds: 100));

    final allowed = evaluator.evaluateState(
      now: now,
      connected: true,
      identity: identity,
      backupAvailable: true,
      speedKph: 0.0,
      lastUpdate: fresh,
      hasFault: false,
    );
    expect(allowed.allowed, isTrue);

    final moving = evaluator.evaluateState(
      now: now,
      connected: true,
      identity: identity,
      backupAvailable: true,
      speedKph: 0.5,
      lastUpdate: fresh,
      hasFault: false,
    );
    expect(moving.allowed, isFalse);
    expect(moving.rejections, contains(SafetyRejection.moving));

    final stale = evaluator.evaluateState(
      now: now,
      connected: true,
      identity: identity,
      backupAvailable: true,
      speedKph: 0.0,
      lastUpdate: now.subtract(const Duration(seconds: 3)),
      hasFault: false,
    );
    expect(stale.allowed, isFalse);
    expect(stale.rejections, contains(SafetyRejection.staleTelemetry));

    final faulted = evaluator.evaluateState(
      now: now,
      connected: true,
      identity: ControllerIdentity(model: 'FD72680', bindingId: 'b'),
      backupAvailable: true,
      speedKph: 0.0,
      lastUpdate: fresh,
      hasFault: true,
    );
    expect(faulted.rejections, contains(SafetyRejection.faultActive));
    expect(faulted.rejections, contains(SafetyRejection.unknownIdentity));

    final offline = evaluator.evaluateState(
      now: now,
      connected: false,
      identity: identity,
      backupAvailable: true,
      speedKph: 0.0,
      lastUpdate: fresh,
      hasFault: false,
    );
    expect(offline.rejections, contains(SafetyRejection.disconnected));
  });

  test('requires fresh consecutive stillness samples and backup', () {
    final now = DateTime.utc(2026, 1, 1);
    final evaluator = const SafetyEvaluator();
    final samples = <SafetySample>[
      _sample(now.subtract(const Duration(milliseconds: 200))),
      _sample(now.subtract(const Duration(milliseconds: 100))),
      _sample(now),
    ];
    expect(
      evaluator
          .evaluate(
            now: now,
            connected: true,
            identity: identity,
            backupAvailable: true,
            samples: samples,
          )
          .allowed,
      isTrue,
    );
    expect(
      evaluator
          .evaluate(
            now: now,
            connected: true,
            identity: identity,
            backupAvailable: false,
            samples: samples,
          )
          .rejections,
      contains(SafetyRejection.missingBackup),
    );
  });

  test('moving or stale telemetry fails closed', () {
    final now = DateTime.utc(2026, 1, 1);
    final decision = const SafetyEvaluator().evaluate(
      now: now,
      connected: true,
      identity: identity,
      backupAvailable: true,
      samples: [
        _sample(now.subtract(const Duration(seconds: 2)), rpm: 1),
      ],
    );
    expect(decision.allowed, isFalse);
    expect(decision.rejections, contains(SafetyRejection.moving));
    expect(decision.rejections, contains(SafetyRejection.staleTelemetry));
    expect(decision.rejections, contains(SafetyRejection.insufficientSamples));
  });
}
