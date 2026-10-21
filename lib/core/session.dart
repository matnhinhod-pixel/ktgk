import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://repeated-citizen-sierra-computing.trycloudflare.com',
);

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

class SessionUser {
  const SessionUser({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
  });

  final String id;
  final String username;
  final String email;
  final String role;

  factory SessionUser.fromJson(Map<String, dynamic> json) => SessionUser(
        id: json['id']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        role: json['role']?.toString() ?? 'Employee',
      );
}

class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _biometricKey = 'biometric_unlock_enabled';
  final FlutterSecureStorage _storage;

  Future<String?> get accessToken => _storage.read(key: _accessKey);
  Future<String?> get refreshToken => _storage.read(key: _refreshKey);
  Future<bool> get biometricUnlockEnabled async =>
      (await _storage.read(key: _biometricKey)) == 'true';

  Future<void> setBiometricUnlockEnabled(bool enabled) =>
      _storage.write(key: _biometricKey, value: enabled.toString());

  Future<void> save(String access, String refresh) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _biometricKey);
  }
}

class ApiClient {
  ApiClient({
    required this.session,
    String baseUrl = apiBaseUrl,
    http.Client? client,
  })  : _baseUri = Uri.parse(baseUrl),
        _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;
  final SessionStore session;
  bool _refreshing = false;

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, [Map<String, dynamic>? body]) =>
      _send('POST', path, body: body);
  Future<dynamic> postPublic(String path, Map<String, dynamic> body) =>
      _send('POST', path, body: body, withAuth: false, allowRefresh: false);
  Future<dynamic> put(String path, Map<String, dynamic> body) =>
      _send('PUT', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool allowRefresh = true,
    bool withAuth = true,
  }) async {
    final uri = _baseUri.resolve(path.startsWith('/') ? path.substring(1) : path);
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (withAuth) {
      final token = await session.accessToken;
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }

    late http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(const Duration(seconds: 20));
      response = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 20));
    } on Exception catch (error) {
      throw ApiException(0, 'Cannot reach the API. Check your network or API URL. $error');
    }

    if (response.statusCode == 401 && withAuth && allowRefresh && !_refreshing) {
      final renewed = await _refreshSession();
      if (renewed) {
        return _send(method, path, body: body, allowRefresh: false, withAuth: withAuth);
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, _errorMessage(response));
    }
    if (response.statusCode == 204 || response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  Future<bool> _refreshSession() async {
    if (_refreshing) return false;
    _refreshing = true;
    try {
      final refresh = await session.refreshToken;
      if (refresh == null || refresh.isEmpty) return false;
      final result = await _send(
        'POST',
        '/api/v1/auth/refresh',
        body: {'refreshToken': refresh},
        allowRefresh: false,
        withAuth: false,
      ) as Map<String, dynamic>;
      await session.save(result['accessToken'] as String, result['refreshToken'] as String);
      return true;
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) await session.clear();
      return false;
    } catch (_) {
      return false;
    } finally {
      _refreshing = false;
    }
  }

  Future<void> logout() async {
    final refresh = await session.refreshToken;
    if (refresh != null) {
      try {
        await _send('POST', '/api/v1/auth/logout', body: {'refreshToken': refresh});
      } catch (_) {
        // Local credentials are still cleared when the API cannot be reached.
      }
    }
    await session.clear();
  }

  String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        final errors = body['errors'];
        if (errors is Map) {
          final messages = <String>[];
          for (final entry in errors.entries) {
            final value = entry.value;
            final details = value is List ? value.join(' ') : value.toString();
            if (details.trim().isNotEmpty) {
              messages.add('${entry.key}: $details');
            }
          }
          if (messages.isNotEmpty) return messages.join('\n');
        }
        return (body['detail'] ?? body['message'] ?? body['title'] ?? 'Request failed').toString();
      }
    } catch (_) {
      if (response.body.isNotEmpty) return response.body;
    }
    return 'Request failed (${response.statusCode}).';
  }
}
