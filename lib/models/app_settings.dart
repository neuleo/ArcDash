class AppSettings {
  final String languageCode;
  final bool useMph;
  final bool useFahrenheit;
  final bool autoReconnect;
  final bool hapticFeedbackEnabled;

  const AppSettings({
    this.languageCode = 'de',
    this.useMph = false,
    this.useFahrenheit = false,
    this.autoReconnect = true,
    this.hapticFeedbackEnabled = true,
  });

  Map<String, dynamic> toJson() => {
        'languageCode': languageCode,
        'useMph': useMph,
        'useFahrenheit': useFahrenheit,
        'autoReconnect': autoReconnect,
        'hapticFeedbackEnabled': hapticFeedbackEnabled,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        languageCode: json['languageCode'] as String? ?? 'de',
        useMph: json['useMph'] as bool? ?? false,
        useFahrenheit: json['useFahrenheit'] as bool? ?? false,
        autoReconnect: json['autoReconnect'] as bool? ?? true,
        hapticFeedbackEnabled: json['hapticFeedbackEnabled'] as bool? ?? true,
      );
}
