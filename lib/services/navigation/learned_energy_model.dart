import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/range_prediction_state.dart';
import 'package:arcdash/providers/controller_provider.dart';

/// Self-learning consumption model that computes a refined Wh/km baseline
/// by combining:
/// 1. Real-time controller learned capacity & ride history
/// 2. Elevation / ascent energy penalties
/// 3. Speed / throttle aggression factors from past trips
class LearnedEnergyModel {
  final double learnedCapacityWh;
  final double baseWhPerKm;
  final double elevationPenaltyWhPerMeter;
  final double regenEfficiency;
  final double confidence;

  const LearnedEnergyModel({
    required this.learnedCapacityWh,
    required this.baseWhPerKm,
    this.elevationPenaltyWhPerMeter = 0.25,
    this.regenEfficiency = 0.08,
    this.confidence = 0.5,
  });

  /// Factory pulling directly from [RangePredictionState].
  factory LearnedEnergyModel.fromRangeState(RangePredictionState? state) {
    if (state == null) {
      return const LearnedEnergyModel(
        learnedCapacityWh: 4000.0,
        baseWhPerKm: 35.0,
        confidence: 0.1,
      );
    }

    final capacity = state.learnedCapacityWh ?? 4000.0;
    double avgWhKm = 35.0;
    if (state.consumptionHistoryWhPerKm.isNotEmpty) {
      final sum = state.consumptionHistoryWhPerKm.reduce((a, b) => a + b);
      avgWhKm = sum / state.consumptionHistoryWhPerKm.length;
    }

    return LearnedEnergyModel(
      learnedCapacityWh: capacity,
      baseWhPerKm: avgWhKm.clamp(15.0, 120.0),
      confidence: state.socConfidence,
    );
  }
}

final learnedEnergyModelProvider = Provider<LearnedEnergyModel>((ref) {
  final rangeState = ref.watch(rangePredictionStateProvider);
  return LearnedEnergyModel.fromRangeState(rangeState);
});
