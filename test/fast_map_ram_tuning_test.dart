import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/fast_map_provider.dart';
import 'package:arcdash/providers/tuning_provider.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/services/write_safety.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tuning_v2_test.dart' as t2;

void main() {
  group('Fast Map & RAM vs Flash Tuning Tests', () {
    test('L1E baseline preset is Stock Street Legal', () {
      final l1e = TuningProfile.l1ePresets();
      expect(l1e, hasLength(1));
      expect(l1e.first.name, 'Stock Street Legal');
      expect(l1e.first.maxSpeedKph, 45.0);
      expect(l1e.first.maxLineCurrA, 80.0);
      expect(l1e.first.isStock, isTrue);
    });

    test('TuningNotifier writes to RAM without saving to Flash by default',
        () async {
      final storage = t2.MemoryStorage();
      final dongle = t2.FakeDongleService();
      final container = ProviderContainer(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(dongle),
          storageServiceProvider.overrideWithValue(storage),
          writeSafetyDecisionProvider.overrideWithValue(
              const SafetyDecision(allowed: true, rejections: {})),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(tuningProvider.notifier);
      final tuned = TuningProfile.defaultTuned();
      notifier.loadPreset(tuned);

      final success = await notifier.applyProfile(saveToFlash: false);
      expect(success, isTrue);

      final state = container.read(tuningProvider);
      expect(state.appliedSuccessfully, isTrue);
      expect(state.lastAppliedWasFlash, isFalse);
      expect(state.activeRamMap, 'Tuned (Offen)');
    });

    test('TuningNotifier writes to Flash when explicitly commanded', () async {
      final storage = t2.MemoryStorage();
      final dongle = t2.FakeDongleService();
      final container = ProviderContainer(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(dongle),
          storageServiceProvider.overrideWithValue(storage),
          writeSafetyDecisionProvider.overrideWithValue(
              const SafetyDecision(allowed: true, rejections: {})),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(tuningProvider.notifier);
      final stock = TuningProfile.stockStreetLegal();
      notifier.loadPreset(stock);

      final success = await notifier.applyProfile(saveToFlash: true);
      expect(success, isTrue);

      final state = container.read(tuningProvider);
      expect(state.appliedSuccessfully, isTrue);
      expect(state.lastAppliedWasFlash, isTrue);
    });

    test('TuningNotifier can clone and rename custom profiles', () async {
      final storage = t2.MemoryStorage();
      final dongle = t2.FakeDongleService();
      final container = ProviderContainer(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(dongle),
          storageServiceProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(tuningProvider.notifier);
      final base = TuningProfile.stockStreetLegal();

      final cloneSuccess =
          await notifier.cloneProfile(base, 'Mein Wald-Profil');
      expect(cloneSuccess, isTrue);
      expect(storage.profiles.any((p) => p.name == 'Mein Wald-Profil'), isTrue);

      final renameSuccess =
          await notifier.renameProfile('Mein Wald-Profil', 'Enduro Boost');
      expect(renameSuccess, isTrue);
      expect(storage.profiles.any((p) => p.name == 'Enduro Boost'), isTrue);
      expect(
          storage.profiles.any((p) => p.name == 'Mein Wald-Profil'), isFalse);
    });

    test('FastMapNotifier manages RAM switching and fast config', () async {
      final storage = t2.MemoryStorage();
      final dongle = t2.FakeDongleService();
      final container = ProviderContainer(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(dongle),
          storageServiceProvider.overrideWithValue(storage),
          writeSafetyDecisionProvider.overrideWithValue(
              const SafetyDecision(allowed: true, rejections: {})),
        ],
      );
      addTearDown(container.dispose);

      final fastNotifier = container.read(fastMapProvider.notifier);
      fastNotifier.setTunedProfileName('Stock Street Legal');
      fastNotifier.setAutoApplyOnConnect(true);

      expect(fastNotifier.state.autoApplyOnConnect, isTrue);
      expect(fastNotifier.state.tunedProfileName, 'Stock Street Legal');

      final ok = await fastNotifier.applyTunedProfile();
      expect(ok, isTrue);
      expect(fastNotifier.state.activeRamMap, 'Stock Street Legal');

      final okStock = await fastNotifier.applyStockProfile();
      expect(okStock, isTrue);
      expect(fastNotifier.state.activeRamMap, 'Stock Street Legal');
    });
  });
}
