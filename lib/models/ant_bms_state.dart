/// Immutable snapshot of decoded ANT BMS telemetry.
///
/// Cell voltages are kept in millivolts (mV) as reported by the BMS,
/// temperatures in degrees Celsius and the pack SOC in percent.
class AntBmsState {
  /// Cell voltages for Cell 1..N in mV (index 0 == Cell 1).
  final List<int> cellVoltagesMv;

  /// NTC battery temperature sensors in °C (max 4).
  final List<double> temperaturesC;

  /// MOSFET / board temperature in °C.
  final double mosfetTemperatureC;

  /// Balancer temperature in °C.
  final double balancerTemperatureC;

  /// Total pack voltage in V.
  final double? totalVoltageV;

  /// Pack current in A (positive = discharge, negative = charge).
  final double? currentA;

  /// BMS reported state of charge in percent.
  final int? socPercent;

  /// State of health in percent.
  final int? sohPercent;

  /// Raw battery status code (0=Unknown, 1=Idle, 2=Charge, 3=Discharge,
  /// 4=Standby, 5=Error).
  final int? batteryStatusCode;

  /// Charge MOSFET switch state.
  final int chargeMosfetStatus;

  /// Discharge MOSFET switch state.
  final int dischargeMosfetStatus;

  /// Balancer switch state.
  final int balancerStatus;

  /// Timestamp of the last decoded status frame.
  final DateTime capturedAt;

  AntBmsState({
    this.cellVoltagesMv = const [],
    this.temperaturesC = const [],
    this.mosfetTemperatureC = 0,
    this.balancerTemperatureC = 0,
    this.totalVoltageV,
    this.currentA,
    this.socPercent,
    this.sohPercent,
    this.batteryStatusCode,
    this.chargeMosfetStatus = 0,
    this.dischargeMosfetStatus = 0,
    this.balancerStatus = 0,
    DateTime? capturedAt,
  }) : capturedAt = capturedAt ?? DateTime.now();

  static AntBmsState initial() => AntBmsState();

  int get cellCount => cellVoltagesMv.length;

  /// Maximum cell voltage in mV, or null when no cells are known.
  int? get maxCellVoltageMv {
    if (cellVoltagesMv.isEmpty) return null;
    return cellVoltagesMv.reduce((a, b) => a > b ? a : b);
  }

  /// Minimum cell voltage in mV, or null when no cells are known.
  int? get minCellVoltageMv {
    if (cellVoltagesMv.isEmpty) return null;
    return cellVoltagesMv.reduce((a, b) => a < b ? a : b);
  }

  /// 1-based index of the highest cell, or null when no cells are known.
  int? get maxCellIndex {
    if (cellVoltagesMv.isEmpty) return null;
    var index = 0;
    for (var i = 1; i < cellVoltagesMv.length; i++) {
      if (cellVoltagesMv[i] > cellVoltagesMv[index]) index = i;
    }
    return index + 1;
  }

  /// 1-based index of the lowest cell, or null when no cells are known.
  int? get minCellIndex {
    if (cellVoltagesMv.isEmpty) return null;
    var index = 0;
    for (var i = 1; i < cellVoltagesMv.length; i++) {
      if (cellVoltagesMv[i] < cellVoltagesMv[index]) index = i;
    }
    return index + 1;
  }

  /// Difference between the highest and lowest cell voltage in mV.
  int get cellDeltaMv {
    final max = maxCellVoltageMv;
    final min = minCellVoltageMv;
    if (max == null || min == null) return 0;
    return max - min;
  }

  /// Average cell voltage in mV, or null when no cells are known.
  int? get averageCellVoltageMv {
    if (cellVoltagesMv.isEmpty) return null;
    var sum = 0;
    for (final voltage in cellVoltagesMv) {
      sum += voltage;
    }
    return (sum / cellVoltagesMv.length).round();
  }

  /// Whether the BMS reports a charge cycle in progress.
  bool get isCharging => batteryStatusCode == 2;

  /// Whether the BMS reports a discharge cycle in progress.
  bool get isDischarging => batteryStatusCode == 3;

  /// Whether the discharge MOSFET switch is closed (on).
  bool get isDischargeMosfetOn => dischargeMosfetStatus == 0x01;

  /// Whether the charge MOSFET switch is closed (on).
  bool get isChargeMosfetOn => chargeMosfetStatus == 0x01;

  AntBmsState copyWith({
    List<int>? cellVoltagesMv,
    List<double>? temperaturesC,
    double? mosfetTemperatureC,
    double? balancerTemperatureC,
    double? totalVoltageV,
    double? currentA,
    int? socPercent,
    int? sohPercent,
    int? batteryStatusCode,
    int? chargeMosfetStatus,
    int? dischargeMosfetStatus,
    int? balancerStatus,
    DateTime? capturedAt,
  }) {
    return AntBmsState(
      cellVoltagesMv: cellVoltagesMv ?? this.cellVoltagesMv,
      temperaturesC: temperaturesC ?? this.temperaturesC,
      mosfetTemperatureC: mosfetTemperatureC ?? this.mosfetTemperatureC,
      balancerTemperatureC: balancerTemperatureC ?? this.balancerTemperatureC,
      totalVoltageV: totalVoltageV ?? this.totalVoltageV,
      currentA: currentA ?? this.currentA,
      socPercent: socPercent ?? this.socPercent,
      sohPercent: sohPercent ?? this.sohPercent,
      batteryStatusCode: batteryStatusCode ?? this.batteryStatusCode,
      chargeMosfetStatus: chargeMosfetStatus ?? this.chargeMosfetStatus,
      dischargeMosfetStatus:
          dischargeMosfetStatus ?? this.dischargeMosfetStatus,
      balancerStatus: balancerStatus ?? this.balancerStatus,
      capturedAt: capturedAt ?? this.capturedAt,
    );
  }
}
