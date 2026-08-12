import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

enum ServiceMessageType { status, streetLegalRequest, result, error }

class ServiceMessage {
  final int version;
  final ServiceMessageType type;
  final String? code;
  final Map<String, Object?> data;

  const ServiceMessage({
    this.version = 1,
    required this.type,
    this.code,
    this.data = const {},
  });

  Map<String, Object?> toJson() => {
        'version': version,
        'type': type.name,
        if (code != null) 'code': code,
        'data': data,
      };

  String encode() => jsonEncode(toJson());

  factory ServiceMessage.decode(Object? value) {
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['type'] is! String) {
      throw const FormatException('invalid service message');
    }
    final type =
        ServiceMessageType.values.where((item) => item.name == decoded['type']);
    if (type.length != 1 || decoded['data'] is! Map) {
      throw const FormatException('unknown service message');
    }
    return ServiceMessage(
      type: type.single,
      code: decoded['code'] as String?,
      data: Map<String, Object?>.from(decoded['data'] as Map),
    );
  }
}

class ForegroundServiceBridge {
  static const MethodChannel _channel =
      MethodChannel('com.arcdash.arcdash/service');

  final StreamController<String> _macroDroidTriggerController =
      StreamController<String>.broadcast();

  ForegroundServiceBridge() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Stream<String> get onMacroDroidTrigger => _macroDroidTriggerController.stream;

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onMacroDroidTrigger') {
      final args = call.arguments as Map?;
      final action = args?['action'] as String? ??
          'com.arcdash.arcdash.APPLY_STREET_LEGAL';
      _macroDroidTriggerController.add(action);
      return true;
    }
    return null;
  }

  Future<void> start() async {
    try {
      await _channel.invokeMethod<void>('start');
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  Future<void> updateNotification(String text) async {
    try {
      await _channel.invokeMethod<void>('updateNotification', {'text': text});
    } catch (_) {}
  }

  Future<void> vibrateSuccess() async {
    try {
      await _channel.invokeMethod<void>('vibrateSuccess');
    } catch (_) {}
  }

  Future<void> vibrateError() async {
    try {
      await _channel.invokeMethod<void>('vibrateError');
    } catch (_) {}
  }

  void dispose() {
    _macroDroidTriggerController.close();
  }
}
