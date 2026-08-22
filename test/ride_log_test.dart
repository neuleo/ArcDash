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

    test('preserves GPS channels', () {
      const s = RideLogSample(
        t: 12,
        gpsLatitude: 50.123456,
        gpsLongitude: 8.654321,
        gpsAltitudeM: 187.4,
        gpsSpeedKph: 33.7,
        gpsAccuracyM: 5.2,
      );
      final restored = RideLogSample.fromJson(s.toJson());
      expect(restored.gpsLatitude, closeTo(50.123456, 1e-9));
      expect(restored.gpsLongitude, closeTo(8.654321, 1e-9));
      expect(restored.gpsAltitudeM, closeTo(187.4, 1e-9));
      expect(restored.gpsSpeedKph, closeTo(33.7, 1e-9));
      expect(restored.gpsAccuracyM, closeTo(5.2, 1e-9));
    });

    test('null channels are omitted and stay null', () {
      const s = RideLogSample(t: 1); // everything null
      final json = s.toJson();
      expect(json.containsKey('s'), isFalse);
      expect(json.containsKey('gla'), isFalse);
      final restored = RideLogSample.fromJson(json);
      expect(restored.speedKph, isNull);
      expect(restored.powerKw, isNull);
      expect(restored.cellDeltaMv, isNull);
      expect(restored.gpsLatitude, isNull);
      expect(restored.gpsAltitudeM, isNull);
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

    test('full log JSON round-trip preserves samples incl. GPS', () {
      var log = RideLog(
        id: 'log_42',
        startedAt: DateTime(2026, 8, 22, 12),
        endedAt: DateTime(2026, 8, 22, 13),
        samples: List.generate(50, sample),
      );
      // Stamp GPS on every third sample
      final stamped = <RideLogSample>[];
      for (final s in log.samples) {
        stamped.add(s.t % 3 == 0
            ? RideLogSample(
                t: s.t,
                speedKph: s.speedKph,
                gpsLatitude: 50.0 + s.t * 0.0001,
                gpsLongitude: 8.0 + s.t * 0.0001,
                gpsAltitudeM: 100 + s.t * 0.5,
                gpsSpeedKph: s.speedKph,
                gpsAccuracyM: 4,
              )
            : s);
      }
      log = RideLog(
        id: log.id,
        startedAt: log.startedAt,
        endedAt: log.endedAt,
        samples: stamped,
      );

      final restored = RideLog.fromJson(log.toJson());
      expect(restored.samples, hasLength(50));
      expect(restored.samples.where((s) => s.gpsLatitude != null).length, 17);
      expect(
        restored.statsFor(RideChannel.voltage).max,
        closeTo(log.statsFor(RideChannel.voltage).max!, 1e-9),
      );
    });

    group('elevation gain/loss with jitter filter', () {
      test('sums only climbs > 1 m as gain', () {
        final alts = [100.0, 101.5, 102.8, 102.9 /* noise */, 105.0];
        final log = RideLog(
          id: 'x',
          startedAt: DateTime(2026),
          endedAt: DateTime(2026),
          samples: List.generate(
              alts.length, (i) => RideLogSample(t: i, gpsAltitudeM: alts[i])),
        );
        // climbs: +1.5 (100→101.5), +1.3, +0.1 ignored, +2.1 → 4.9
        expect(log.elevationGainM, closeTo(4.9, 0.001));
      });

      test('sums descents > 1 m as loss', () {
        final alts = [200.0, 198.0, 197.5, 195.0];
        final log = RideLog(
          id: 'x',
          startedAt: DateTime(2026),
          endedAt: DateTime(2026),
          samples: List.generate(
              alts.length, (i) => RideLogSample(t: i, gpsAltitudeM: alts[i])),
        );
        // drops: -2.0, -0.5 ignored, -2.5 → 4.5
        expect(log.elevationLossM, closeTo(4.5, 0.001));
        expect(log.elevationGainM, 0);
      });

      test('null when no altitude data', () {
        final log = RideLog(
          id: 'x',
          startedAt: DateTime(2026),
          endedAt: DateTime(2026),
          samples: const [RideLogSample(t: 0, speedKph: 10)],
        );
        expect(log.elevationGainM, isNull);
        expect(log.elevationLossM, isNull);
        expect(log.gpsTrack, isEmpty);
      });

      test('gpsTrack filters low-accuracy fixes', () {
        final log = RideLog(
          id: 'x',
          startedAt: DateTime(2026),
          endedAt: DateTime(2026),
          samples: const [
            RideLogSample(
                t: 0, gpsLatitude: 50.0, gpsLongitude: 8.0, gpsAccuracyM: 5),
            RideLogSample(
                t: 1, gpsLatitude: 50.1, gpsLongitude: 8.1, gpsAccuracyM: 80),
            RideLogSample(
                t: 2, gpsLatitude: 50.2, gpsLongitude: 8.2, gpsAccuracyM: 12),
          ],
        );
        expect(log.gpsTrack, hasLength(2));
        expect(log.gpsTrack.first.$1, 50.0);
        expect(log.gpsTrack.last.$1, 50.2);
      });

      test('mixed gain and loss over a hilly ride', () {
        final alts = [100, 104, 106, 98, 95, 102];
        final log = RideLog(
          id: 'x',
          startedAt: DateTime(2026),
          endedAt: DateTime(2026),
          samples: List.generate(alts.length,
              (i) => RideLogSample(t: i, gpsAltitudeM: alts[i].toDouble())),
        );
        // gains (> 1 m): +4, +2, +7 → 13 ; losses (> 1 m): -8, -3 → 11
        expect(log.elevationGainM, closeTo(13, 0.001));
        expect(log.elevationLossM, closeTo(11, 0.001));
      });
    });

    test('valueOf maps every channel to its field', () {
      const s = RideLogSample(
        t: 0,
        speedKph: 10,
        packVoltageV: 84,
        cellDeltaMv: 4,
        gpsSpeedKph: 11,
        gpsAltitudeM: 120,
      );
      expect(RideLog.valueOf(s, RideChannel.speed), 10);
      expect(RideLog.valueOf(s, RideChannel.packVoltage), 84);
      expect(RideLog.valueOf(s, RideChannel.cellDelta), 4);
      expect(RideLog.valueOf(s, RideChannel.gpsSpeed), 11);
      expect(RideLog.valueOf(s, RideChannel.gpsAltitude), 120);
    });
  });

  group('Channel catalog', () {
    test('all 13 channels have label and unit', () {
      for (final c in RideChannel.values) {
        expect(c.label, isNotEmpty, reason: '${c.name} missing label');
        expect(c.unit, isNotEmpty, reason: '${c.name} missing unit');
      }
      expect(RideChannel.values, hasLength(13));
    });
  });
}
