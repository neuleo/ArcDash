/// One recorded telemetry sample of a ride (1 Hz default).
///
/// All values nullable: a channel that was unavailable at that second is
/// stored as null and skipped in statistics.
class RideLogSample {
  /// Seconds since ride start (integer, 1 Hz grid).
  final int t;

  final double? speedKph;
  final double? powerKw; // signed: negative = regen
  final double? voltageV;
  final double? currentA; // signed
  final double? motorTempC;
  final double? controllerTempC;
  final double? socPercent;

  // ANT BMS channels (null without BMS)
  final double? packVoltageV;
  final double? bmsCurrentA;
  final double? bmsTempC;
  final int? cellDeltaMv;

  const RideLogSample({
    required this.t,
    this.speedKph,
    this.powerKw,
    this.voltageV,
    this.currentA,
    this.motorTempC,
    this.controllerTempC,
    this.socPercent,
    this.packVoltageV,
    this.bmsCurrentA,
    this.bmsTempC,
    this.cellDeltaMv,
  });

  Map<String, dynamic> toJson() => {
        't': t,
        if (speedKph != null) 's': speedKph,
        if (powerKw != null) 'p': powerKw,
        if (voltageV != null) 'u': voltageV,
        if (currentA != null) 'i': currentA,
        if (motorTempC != null) 'tm': motorTempC,
        if (controllerTempC != null) 'tc': controllerTempC,
        if (socPercent != null) 'soc': socPercent,
        if (packVoltageV != null) 'bu': packVoltageV,
        if (bmsCurrentA != null) 'bi': bmsCurrentA,
        if (bmsTempC != null) 'bt': bmsTempC,
        if (cellDeltaMv != null) 'd': cellDeltaMv,
      };

  factory RideLogSample.fromJson(Map<String, dynamic> j) => RideLogSample(
        t: j['t'] as int,
        speedKph: (j['s'] as num?)?.toDouble(),
        powerKw: (j['p'] as num?)?.toDouble(),
        voltageV: (j['u'] as num?)?.toDouble(),
        currentA: (j['i'] as num?)?.toDouble(),
        motorTempC: (j['tm'] as num?)?.toDouble(),
        controllerTempC: (j['tc'] as num?)?.toDouble(),
        socPercent: (j['soc'] as num?)?.toDouble(),
        packVoltageV: (j['bu'] as num?)?.toDouble(),
        bmsCurrentA: (j['bi'] as num?)?.toDouble(),
        bmsTempC: (j['bt'] as num?)?.toDouble(),
        cellDeltaMv: (j['d'] as num?)?.toInt(),
      );
}

/// Recordable channels shown in the analysis UI.
enum RideChannel {
  speed('Geschwindigkeit', 'km/h'),
  power('Leistung', 'kW'),
  voltage('Spannung (Ctrl)', 'V'),
  current('Strom (Ctrl)', 'A'),
  motorTemp('Motortemp', '°C'),
  controllerTemp('Controllertemp', '°C'),
  soc('Ladestand', '%'),
  packVoltage('Packspannung (BMS)', 'V'),
  bmsCurrent('BMS-Strom', 'A'),
  bmsTemp('Akku-Temp (NTC)', '°C'),
  cellDelta('Zell-Delta', 'mV');

  final String label;
  final String unit;
  const RideChannel(this.label, this.unit);
}

/// Min/Max/Average triple of one channel over a ride.
class ChannelStats {
  final double? min;
  final double? max;
  final double? avg;
  final int count;

  const ChannelStats({this.min, this.max, this.avg, this.count = 0});
}

/// Complete ride log of one session.
class RideLog {
  static const int maxSamplesPerLog = 14400; // 4 h @ 1 Hz hard cap

  final DateTime startedAt;
  final DateTime endedAt;
  final List<RideLogSample> samples;
  final String id;

  const RideLog({
    required this.startedAt,
    required this.endedAt,
    required this.samples,
    required this.id,
  });

  Duration get duration => endedAt.difference(startedAt);

  /// Distance integrated from speed samples (km).
  double get distanceKm {
    var km = 0.0;
    for (final s in samples) {
      final v = s.speedKph;
      if (v != null) km += v / 3600.0; // 1 s step
    }
    return km;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'samples': samples.map((s) => s.toJson()).toList(),
      };

  factory RideLog.fromJson(Map<String, dynamic> j) => RideLog(
        id: j['id'] as String,
        startedAt: DateTime.parse(j['startedAt'] as String),
        endedAt: DateTime.parse(j['endedAt'] as String),
        samples: (j['samples'] as List<dynamic>? ?? const [])
            .map((e) => RideLogSample.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// Value of [channel] inside [sample] (null when not recorded).
  static double? valueOf(RideLogSample s, RideChannel c) => switch (c) {
        RideChannel.speed => s.speedKph,
        RideChannel.power => s.powerKw,
        RideChannel.voltage => s.voltageV,
        RideChannel.current => s.currentA,
        RideChannel.motorTemp => s.motorTempC,
        RideChannel.controllerTemp => s.controllerTempC,
        RideChannel.soc => s.socPercent,
        RideChannel.packVoltage => s.packVoltageV,
        RideChannel.bmsCurrent => s.bmsCurrentA,
        RideChannel.bmsTemp => s.bmsTempC,
        RideChannel.cellDelta => s.cellDeltaMv?.toDouble(),
      };

  /// Min/Max/Average of [channel] across all non-null samples.
  ChannelStats statsFor(RideChannel channel) {
    double? min, max, sum;
    var count = 0;
    for (final s in samples) {
      final v = valueOf(s, channel);
      if (v == null) continue;
      if (min == null || v < min) min = v;
      if (max == null || v > max) max = v;
      sum = (sum ?? 0) + v;
      count++;
    }
    return ChannelStats(
      min: min,
      max: max,
      avg: count > 0 ? sum! / count : null,
      count: count,
    );
  }
}
