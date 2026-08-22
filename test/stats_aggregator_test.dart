import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/session_metrics.dart';
import 'package:arcdash/services/session_history_repository.dart';
import 'package:arcdash/services/stats_aggregator.dart';

SessionRecord rec(
  String id,
  DateTime start, {
  double km = 10,
  double whPerKm = 50,
  double maxSpeed = 60,
  int minutes = 30,
}) {
  return SessionRecord(
    id: id,
    startTime: start,
    endTime: start.add(Duration(minutes: minutes)),
    metrics: SessionMetrics(
      duration: Duration(minutes: minutes),
      distanceKm: km,
      avgSpeedKph: minutes > 0 ? km / (minutes / 60) : 0,
      maxSpeedKph: maxSpeed,
      consumedWh: km * whPerKm,
      recoveredWh: 0,
      netWh: km * whPerKm,
      whPerKm: km > 0 ? whPerKm : 0,
      maxPowerKw: 8,
      isIncomplete: false,
    ),
  );
}

void main() {
  group('SessionStatsAggregator', () {
    test('aggregates totals, top speed and duration across sessions', () {
      final base = DateTime(2026, 8, 10, 10);
      final records = [
        rec('a', base, km: 20, maxSpeed: 65, minutes: 40),
        rec('b', base.add(const Duration(days: 1)),
            km: 30, maxSpeed: 72, minutes: 60),
      ];
      final agg = SessionStatsAggregator.aggregate(records);
      expect(agg.totalKm, closeTo(50, 0.001));
      expect(agg.topSpeedKph, 72);
      expect(agg.totalDuration, const Duration(minutes: 100));
    });

    test('km per day is summed per calendar day', () {
      final base = DateTime(2026, 8, 10, 8);
      final records = [
        rec('a', base, km: 12),
        rec('b', base.add(const Duration(hours: 4)), km: 8),
        rec('c', base.add(const Duration(days: 1)), km: 25),
      ];
      final agg = SessionStatsAggregator.aggregate(records);
      expect(agg.kmPerDay['2026-08-10'], closeTo(20, 0.001));
      expect(agg.kmPerDay['2026-08-11'], closeTo(25, 0.001));
    });

    test('whPerKm series only includes sessions with > 0.5 km', () {
      final base = DateTime(2026, 8, 10, 8);
      final records = [
        rec('a', base, km: 20, whPerKm: 55),
        rec('b', base.add(const Duration(hours: 2)), km: 0.2, whPerKm: 999),
        rec('c', base.add(const Duration(days: 1)), km: 10, whPerKm: 45),
      ];
      final agg = SessionStatsAggregator.aggregate(records);
      expect(agg.whPerKmSeries, [55, 45]);
      expect(agg.avgWhPerKm, closeTo(50, 0.001));
      expect(agg.bestWhPerKm, 45);
    });

    test('efficiency delta: lower consumption than average is positive', () {
      final base = DateTime(2026, 8, 10, 8);
      final records = [
        rec('a', base, km: 20, whPerKm: 60),
        rec('b', base.add(const Duration(days: 1)), km: 20, whPerKm: 40),
      ];
      final agg = SessionStatsAggregator.aggregate(records);
      // avg = 50; a session at 40 → (60-40)/50 = +20 %
      expect(agg.efficiencyDeltaPercent(40), closeTo(20, 0.01));
      // a session at 60 → (50-60)/50 = -20 %
      expect(agg.efficiencyDeltaPercent(60), closeTo(-20, 0.01));
      expect(agg.efficiencyDeltaPercent(50), closeTo(0, 0.001));
    });

    test('efficiency delta returns null without history', () {
      final agg = SessionStatsAggregator.aggregate([]);
      expect(agg.efficiencyDeltaPercent(50), isNull);
      expect(agg.bestWhPerKm, isNull);
      expect(agg.longestRideKm, isNull);
    });

    test('lastDaysKm zero-fills gaps and is chronological', () {
      final today = DateTime(2026, 8, 14);
      final kmPerDay = {
        '2026-08-12': 15.0,
        '2026-08-14': 22.5,
      };
      final days =
          SessionStatsAggregator.lastDaysKm(kmPerDay, days: 5, today: today);
      expect(days, hasLength(5));
      expect(days[0].$1, '2026-08-10');
      expect(days[0].$2, 0);
      expect(days[2].$1, '2026-08-12');
      expect(days[2].$2, 15.0);
      expect(days[4].$1, '2026-08-14');
      expect(days[4].$2, 22.5);
    });

    test('unsorted input is handled chronologically', () {
      final base = DateTime(2026, 8, 10, 8);
      final records = [
        rec('late', base.add(const Duration(days: 2)), km: 5, whPerKm: 48),
        rec('early', base, km: 10, whPerKm: 52),
      ];
      final agg = SessionStatsAggregator.aggregate(records);
      expect(agg.whPerKmSeries, [52, 48]);
    });
  });
}
