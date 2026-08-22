import 'package:arcdash/services/session_history_repository.dart';

/// Aggregated statistics over a set of sessions (see
/// plan/15-temperatur-management.md, Feature 5).
class StatsAggregates {
  /// Distance per calendar day (ISO yyyy-MM-dd), oldest first.
  final Map<String, double> kmPerDay;

  /// Wh/km per session, oldest first (only sessions with distance > 0.5 km).
  final List<double> whPerKmSeries;

  /// Total km across all sessions.
  final double totalKm;

  /// Total riding time across all sessions.
  final Duration totalDuration;

  /// Highest recorded speed.
  final double topSpeedKph;

  /// Average consumption across qualifying sessions.
  final double avgWhPerKm;

  const StatsAggregates({
    required this.kmPerDay,
    required this.whPerKmSeries,
    required this.totalKm,
    required this.totalDuration,
    required this.topSpeedKph,
    required this.avgWhPerKm,
  });

  /// Longest single ride in km (null without history).
  double? get longestRideKm => kmPerDay.values.isEmpty
      ? null
      : kmPerDay.values.reduce((a, b) => a > b ? a : b);

  /// Best (lowest) consumption of all qualifying sessions, or null.
  double? get bestWhPerKm => whPerKmSeries.isEmpty
      ? null
      : whPerKmSeries.reduce((a, b) => a < b ? a : b);

  /// Efficiency delta of [sessionWhPerKm] vs the personal average in percent.
  /// Positive = more efficient than average.
  double? efficiencyDeltaPercent(double sessionWhPerKm) {
    if (avgWhPerKm <= 0) return null;
    return (avgWhPerKm - sessionWhPerKm) / avgWhPerKm * 100;
  }
}

/// Pure aggregation helpers over the persisted session history.
class SessionStatsAggregator {
  /// Aggregates the given [records] (any order) into [StatsAggregates].
  static StatsAggregates aggregate(List<SessionRecord> records) {
    final sorted = [...records]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final kmPerDay = <String, double>{};
    final whPerKm = <double>[];
    var totalKm = 0.0;
    var totalMs = 0;
    var topSpeed = 0.0;
    var consSum = 0.0;

    for (final r in sorted) {
      final day = '${r.startTime.year.toString().padLeft(4, '0')}-'
          '${r.startTime.month.toString().padLeft(2, '0')}-'
          '${r.startTime.day.toString().padLeft(2, '0')}';
      kmPerDay[day] = (kmPerDay[day] ?? 0) + r.metrics.distanceKm;
      totalKm += r.metrics.distanceKm;
      totalMs += r.metrics.duration.inMilliseconds;
      if (r.metrics.maxSpeedKph > topSpeed) topSpeed = r.metrics.maxSpeedKph;
      if (r.metrics.distanceKm > 0.5) {
        whPerKm.add(r.metrics.whPerKm);
        consSum += r.metrics.whPerKm;
      }
    }

    return StatsAggregates(
      kmPerDay: kmPerDay,
      whPerKmSeries: whPerKm,
      totalKm: totalKm,
      totalDuration: Duration(milliseconds: totalMs),
      topSpeedKph: topSpeed,
      avgWhPerKm: whPerKm.isEmpty ? 0 : consSum / whPerKm.length,
    );
  }

  /// Last [days] calendar days ending today (or the newest known day),
  /// zero-filled so charts show gaps honestly.
  static List<(String, double)> lastDaysKm(Map<String, double> kmPerDay,
      {int days = 14, DateTime? today}) {
    final effectiveToday = today ?? DateTime.now();
    final result = <(String, double)>[];
    for (var i = days - 1; i >= 0; i--) {
      final d = effectiveToday.subtract(Duration(days: i));
      final key = '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      result.add((key, kmPerDay[key] ?? 0));
    }
    return result;
  }
}
