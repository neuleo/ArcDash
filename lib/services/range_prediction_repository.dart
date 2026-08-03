import 'dart:convert';
import 'package:arcdash/models/range_prediction_state.dart';

abstract class KeyValueStorage {
  String? read(String key);
  void write(String key, String value);
  void delete(String key);
}

class MemoryStorage implements KeyValueStorage {
  final Map<String, String> _data = {};

  @override
  String? read(String key) => _data[key];

  @override
  void write(String key, String value) => _data[key] = value;

  @override
  void delete(String key) => _data.remove(key);
}

class RangePredictionRepository {
  static const String _storageKey = 'range_prediction_state';
  final KeyValueStorage _storage;

  RangePredictionRepository({required KeyValueStorage storage})
      : _storage = storage;

  void saveState(RangePredictionState state) {
    final rawJson = jsonEncode(state.toJson());
    _storage.write(_storageKey, rawJson);
  }

  RangePredictionState? loadState({required String controllerId}) {
    try {
      final raw = _storage.read(_storageKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final state = RangePredictionState.fromJson(decoded);
      if (state.controllerId != controllerId) return null;
      return state;
    } catch (_) {
      return null;
    }
  }

  void resetState() {
    _storage.delete(_storageKey);
  }
}
