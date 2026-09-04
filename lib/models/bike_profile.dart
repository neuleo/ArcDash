import 'dart:convert';

/// Represents a configured bike pairing a FarDriver Controller and an ANT BMS.
class BikeProfile {
  final String id;
  final String name;
  final String controllerId;
  final String controllerName;
  final String bmsId;
  final String bmsName;
  final DateTime createdAt;

  const BikeProfile({
    required this.id,
    required this.name,
    required this.controllerId,
    this.controllerName = 'FarDriver Controller',
    this.bmsId = '',
    this.bmsName = 'ANT BMS',
    required this.createdAt,
  });

  bool get hasBms => bmsId.isNotEmpty;

  BikeProfile copyWith({
    String? id,
    String? name,
    String? controllerId,
    String? controllerName,
    String? bmsId,
    String? bmsName,
    DateTime? createdAt,
  }) {
    return BikeProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      controllerId: controllerId ?? this.controllerId,
      controllerName: controllerName ?? this.controllerName,
      bmsId: bmsId ?? this.bmsId,
      bmsName: bmsName ?? this.bmsName,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'controllerId': controllerId,
        'controllerName': controllerName,
        'bmsId': bmsId,
        'bmsName': bmsName,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BikeProfile.fromJson(Map<String, dynamic> json) {
    return BikeProfile(
      id: json['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'Mein Bike',
      controllerId: json['controllerId'] as String? ?? '',
      controllerName:
          json['controllerName'] as String? ?? 'FarDriver Controller',
      bmsId: json['bmsId'] as String? ?? '',
      bmsName: json['bmsName'] as String? ?? 'ANT BMS',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  factory BikeProfile.fromJsonString(String str) =>
      BikeProfile.fromJson(jsonDecode(str) as Map<String, dynamic>);
}
