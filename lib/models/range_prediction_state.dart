class RangePredictionState {
  final int schemaVersion;
  final String controllerId;
  final double? learnedCapacityWh;
  final List<double> consumptionHistoryWhPerKm;
  final double socConfidence;

  const RangePredictionState({
    this.schemaVersion = 1,
    required this.controllerId,
    this.learnedCapacityWh,
    this.consumptionHistoryWhPerKm = const [],
    this.socConfidence = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'controllerId': controllerId,
        'learnedCapacityWh': learnedCapacityWh,
        'consumptionHistoryWhPerKm': consumptionHistoryWhPerKm,
        'socConfidence': socConfidence,
      };

  factory RangePredictionState.fromJson(Map<String, dynamic> json) {
    final rawHistory = json['consumptionHistoryWhPerKm'] as List?;
    return RangePredictionState(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      controllerId: json['controllerId'] as String? ?? '',
      learnedCapacityWh: (json['learnedCapacityWh'] as num?)?.toDouble(),
      consumptionHistoryWhPerKm: rawHistory != null
          ? rawHistory.map((e) => (e as num).toDouble()).toList()
          : const [],
      socConfidence: (json['socConfidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
