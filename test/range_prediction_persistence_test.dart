import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/range_prediction_state.dart';
import 'package:arcdash/services/range_prediction_repository.dart';

void main() {
  group('T068 Range Prediction Persistence (Learned State)', () {
    test('serialization round-trip preserves capacity and consumption history',
        () {
      const state = RangePredictionState(
        schemaVersion: 1,
        controllerId: 'FD-72600-A1',
        learnedCapacityWh: 2450.5,
        consumptionHistoryWhPerKm: [22.5, 24.0, 21.8],
        socConfidence: 0.85,
      );

      final jsonMap = state.toJson();
      final restored = RangePredictionState.fromJson(jsonMap);

      expect(restored.schemaVersion, 1);
      expect(restored.controllerId, 'FD-72600-A1');
      expect(restored.learnedCapacityWh, 2450.5);
      expect(restored.consumptionHistoryWhPerKm, [22.5, 24.0, 21.8]);
      expect(restored.socConfidence, 0.85);
    });

    test('corrupted or mismatching controller ID resets to safe initial state',
        () {
      final repository = RangePredictionRepository(storage: MemoryStorage());

      // Save state for controller A
      const stateA = RangePredictionState(
        schemaVersion: 1,
        controllerId: 'CONTROLLER-A',
        learnedCapacityWh: 3000.0,
        consumptionHistoryWhPerKm: [25.0],
      );
      repository.saveState(stateA);

      // Loading for controller B must return null / safe default
      final loadedB = repository.loadState(controllerId: 'CONTROLLER-B');
      expect(loadedB, isNull);

      // Loading for controller A returns stored state
      final loadedA = repository.loadState(controllerId: 'CONTROLLER-A');
      expect(loadedA, isNotNull);
      expect(loadedA!.learnedCapacityWh, 3000.0);
    });

    test('corrupt JSON or legacy schema triggers controlled reset', () {
      final storage = MemoryStorage();
      storage.write('range_prediction_state', 'invalid-json-content{');

      final repository = RangePredictionRepository(storage: storage);
      final loaded = repository.loadState(controllerId: 'ANY');
      expect(loaded, isNull);
    });
  });
}
