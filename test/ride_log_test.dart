import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/ride_log.dart';

RideLogSample sample(int t) => RideLogSample(
      t: t,
      speedKph: 20.0 + t, // rising
      powerKw: t % 2 == 0 ? 5.5 : -3.0,
      voltageV: 84 - t * 0.01,
      currentA: 60 + t.toDouble(),
      motorTempC: 30 + t * 0.05,
      controllerTempC: 28 + t * 0.04,
      socPercent: 90 - t * 0.01,
      packVoltageV: 83.9 - t * 0.01,
      bmsCurrentA: 59 + t.toDouble(),
      bmsTempC: 25 + t * 0.02,
      cellDeltaMv: 4 + (t % 10),
    );

void main() {
  group('RideLogSample JSON round-trip', () {
    test('preserves all channels', () {
      final s = sample(7);
      final restored = RideLogSample.fromJson(s.toJson());
      expect(restored.t, 7);
      expect(restored.speedKph, s.speedKph);
      expect(restored.powerKw, s.powerKw);
      expect(restored.voltageV, closeTo(s.voltageV!, 1e-9));
      expect(restored.currentA, s.currentA);
      expect(restored.motorTempC, closeTo(s.motorTempC!, 1e-9));
      expect(restored.socPercent, s.socPercent);
      expect(restored.packVoltageV, closeTo(s.packVoltageV!, 1e-9));
      expect(restored.bmsCurrentA, s.bmsCurrentA);
      expect(restored.cellDeltaMv, s.cellDeltaMv);
    });

    test('null channels are omitted and stay null', () {
      const s = RideLogSample(t: 1); // everything null
      final json = s.toJson();
      expect(json.containsKey('s'), isFalse);
      final restored = RideLogSample.fromJson(json);
      expect(restored.speedKph, isNull);
      expect(restored.powerKw, isNull);
      expect(restored.cellDeltaMv, isNull);
    });
  });

  group('RideLog', () {
    test('distance integrates speed over 1 s steps', () {
      // Constant 36 km/h for 100 samples = 36 km/h * (100/3600) h = 1 km
      final log = RideLog(
        id: 'x',
        startedAt: DateTime(2026),
        endedAt: DateTime(2026).add(const Duration(seconds: 100)),
        samples: List.generate(
          100,
          (i) => RideLogSample(t: i, speedKph: 36.0),
        ),
      );
      expect(log.distanceKm, closeTo(1.0, 0.001));
    });

    test('statsFor computes min/max/avg ignoring null gaps', () {
      final log = RideLog(
        id: 'x',
        startedAt: DateTime(2026),
        endedAt: DateTime(2026),
        samples: const [
          RideLogSample(t: 0, speedKph: 10),
          RideLogSample(t: 1), // gap
          RideLogSample(t: 2, speedKph: 30),
          RideLogSample(t: 3, speedKph: 20),
        ],
      );
      final st = log.statsFor(RideChannel.speed);
      expect(st.min, 10);
      expect(st.max, 30);
      expect(st.avg, closeTo(20, 0.001));
      expect(st.count, 3);
    });

    test('statsFor on unrecorded channel returns empty stats', () {
      final log = RideLog(
        id: 'x',
        startedAt: DateTime(2026),
        endedAt: DateTime(2026),
        samples: const [RideLogSample(t: 0, speedKph: 10)],
      );
      final st = log.statsFor(RideChannel.cellDelta);
      expect(st.min, isNull);
      expect(st.max, isNull);
      expect(st.avg, isNull);
      expect(st.count, 0);
    });

    test('full log JSON round-trip preserves samples', () {
      final log = RideLog(
        id: 'log_42',
        startedAt: DateTime(2026, 8, 22, 12),
        endedAt: DateTime(2026, 8, 22, 13),
        samples: List.generate(50, sample),
      );
      final restored = RideLog.fromJson(log.toJson());
      expect(restored.id, 'log_42');
      expect(restored.samples, hasLength(50));
      expect(restored.duration, log.duration);
      expect(
        restored.statsFor(RideChannel.voltage).max,
        closeTo(log.statsFor(RideChannel.voltage).max!, 1e-9),
      );
    });

    test('valueOf maps every channel to its field', () {
      final s = sample(0);
      expect(RideLog.valueOf(s, RideChannel.speed), s.speedKph);
      expect(RideLog.valueOf(s, RideChannel.packVoltage), s.packVoltageV);
      expect(
          RideLog.valueOf(s, RideChannel.cellDelta), s.cellDeltaMv!.toDouble());
    });
  });

  group('Channel catalog', () {
    test('all 11 channels have label and unit', () {
      for (final c in RideChannel.values) {
        expect(c.label, isNotEmpty, reason: '${c.name} missing label');
        expect(c.unit, isNotEmpty, reason: '${c.name} missing unit');
      }
      expect(RideChannel.values, hasLength(11));
    });
  });
}
