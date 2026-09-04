import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class SyncServerConfig {
  final String serverUrl;
  final String? token;
  final String? userId;
  final String? username;

  const SyncServerConfig({
    required this.serverUrl,
    this.token,
    this.userId,
    this.username,
  });

  bool get isAuthenticated => token != null && token!.isNotEmpty;

  SyncServerConfig copyWith({
    String? serverUrl,
    String? token,
    String? userId,
    String? username,
    bool clearAuth = false,
  }) {
    return SyncServerConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      token: clearAuth ? null : (token ?? this.token),
      userId: clearAuth ? null : (userId ?? this.userId),
      username: clearAuth ? null : (username ?? this.username),
    );
  }

  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl,
        'token': token,
        'userId': userId,
        'username': username,
      };

  factory SyncServerConfig.fromJson(Map<String, dynamic> json) {
    return SyncServerConfig(
      serverUrl: json['serverUrl'] as String? ?? 'http://172.24.1.1:8080',
      token: json['token'] as String?,
      userId: json['userId'] as String?,
      username: json['username'] as String?,
    );
  }
}

class SyncApiClient {
  final http.Client _client;

  SyncApiClient({http.Client? client}) : _client = client ?? http.Client();

  Future<Map<String, dynamic>> register({
    required String serverUrl,
    required String username,
    required String password,
    String? email,
  }) async {
    final uri = Uri.parse('$serverUrl/api/v1/auth/register');
    final res = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'email': email,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else {
      final err = jsonDecode(res.body);
      throw HttpException(err['detail'] ?? 'Registrierung fehlgeschlagen');
    }
  }

  Future<Map<String, dynamic>> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final uri = Uri.parse('$serverUrl/api/v1/auth/login');
    final res = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else {
      final err = jsonDecode(res.body);
      throw HttpException(err['detail'] ?? 'Login fehlgeschlagen');
    }
  }

  Future<Map<String, dynamic>> pushSync({
    required String serverUrl,
    required String token,
    required Map<String, dynamic> payload,
  }) async {
    final uri = Uri.parse('$serverUrl/api/v1/sync/push');
    final res = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else {
      throw HttpException('Sync Push fehlgeschlagen (${res.statusCode})');
    }
  }

  Future<Map<String, dynamic>> pullSync({
    required String serverUrl,
    required String token,
    DateTime? since,
  }) async {
    var urlStr = '$serverUrl/api/v1/sync/pull';
    if (since != null) {
      urlStr += '?since=${Uri.encodeComponent(since.toIso8601String())}';
    }
    final uri = Uri.parse(urlStr);
    final res = await _client.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
      },
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else {
      throw HttpException('Sync Pull fehlgeschlagen (${res.statusCode})');
    }
  }
}
