import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum AppText {
  cockpit,
  rides,
  settings,
  connect,
  live,
  rideComputer,
  editDashboard,
  closeEditor,
  addValue,
  copyOrientation,
  defaultLayout,
  portrait,
  landscape,
  moveLeft,
  moveRight,
  moveUp,
  moveDown,
  resize,
  remove,
  controller,
  noData,
  power,
  regeneration,
  noErrors,
  error,
  connected,
  disconnected,
}

class AppStrings {
  final Locale locale;

  const AppStrings(this.locale);

  static const delegate = _AppStringsDelegate();
  static const supportedLocales = [Locale('de'), Locale('en')];

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings)!;
  }

  bool get _english => locale.languageCode == 'en';

  String text(AppText key) => (_english ? _englishText : _germanText)[key]!;

  String metric(String name) {
    final values = _english ? _englishMetrics : _germanMetrics;
    return values[name] ?? name;
  }
}

const _germanText = {
  AppText.cockpit: 'Cockpit',
  AppText.rides: 'Fahrten',
  AppText.settings: 'Einstellungen',
  AppText.connect: 'VERBINDEN',
  AppText.live: 'LIVE',
  AppText.rideComputer: 'FAHR-COMPUTER',
  AppText.editDashboard: 'Dashboard bearbeiten',
  AppText.closeEditor: 'Bearbeitung schließen',
  AppText.addValue: 'Wert hinzufügen',
  AppText.copyOrientation: 'Ausrichtung kopieren',
  AppText.defaultLayout: 'Standardlayout',
  AppText.portrait: 'Hoch',
  AppText.landscape: 'Quer',
  AppText.moveLeft: 'Nach links',
  AppText.moveRight: 'Nach rechts',
  AppText.moveUp: 'Nach oben',
  AppText.moveDown: 'Nach unten',
  AppText.resize: 'Größe ändern',
  AppText.remove: 'Entfernen',
  AppText.controller: 'CONTROLLER',
  AppText.noData: 'KEINE DATEN',
  AppText.power: 'LEISTUNG',
  AppText.regeneration: 'REKUPERATION',
  AppText.noErrors: 'Keine Fehler',
  AppText.error: 'Fehler',
  AppText.connected: 'Verbunden',
  AppText.disconnected: 'Getrennt',
};

const _englishText = {
  AppText.cockpit: 'Cockpit',
  AppText.rides: 'Rides',
  AppText.settings: 'Settings',
  AppText.connect: 'CONNECT',
  AppText.live: 'LIVE',
  AppText.rideComputer: 'RIDE COMPUTER',
  AppText.editDashboard: 'Edit dashboard',
  AppText.closeEditor: 'Close editor',
  AppText.addValue: 'Add value',
  AppText.copyOrientation: 'Copy orientation',
  AppText.defaultLayout: 'Default layout',
  AppText.portrait: 'Portrait',
  AppText.landscape: 'Landscape',
  AppText.moveLeft: 'Move left',
  AppText.moveRight: 'Move right',
  AppText.moveUp: 'Move up',
  AppText.moveDown: 'Move down',
  AppText.resize: 'Resize',
  AppText.remove: 'Remove',
  AppText.controller: 'CONTROLLER',
  AppText.noData: 'NO DATA',
  AppText.power: 'POWER',
  AppText.regeneration: 'REGENERATION',
  AppText.noErrors: 'No errors',
  AppText.error: 'Error',
  AppText.connected: 'Connected',
  AppText.disconnected: 'Disconnected',
};

const _germanMetrics = {
  'speed': 'Geschwindigkeit',
  'power': 'Leistung',
  'voltage': 'Spannung',
  'current': 'Strom',
  'soc': 'Batterie',
  'range': 'Reichweite',
  'profile': 'Profil',
  'gear': 'Gang',
  'motorTemperature': 'Motortemperatur',
  'controllerTemperature': 'Controllertemperatur',
  'errors': 'Fehler',
  'connection': 'Verbindung',
};

const _englishMetrics = {
  'speed': 'Speed',
  'power': 'Power',
  'voltage': 'Voltage',
  'current': 'Current',
  'soc': 'Battery',
  'range': 'Range',
  'profile': 'Profile',
  'gear': 'Gear',
  'motorTemperature': 'Motor temperature',
  'controllerTemperature': 'Controller temperature',
  'errors': 'Errors',
  'connection': 'Connection',
};

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) => AppStrings.supportedLocales
      .any((item) => item.languageCode == locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture(AppStrings(locale));

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
