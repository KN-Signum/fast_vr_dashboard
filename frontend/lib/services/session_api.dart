import 'dart:convert';

import 'package:http/http.dart' as http;

abstract interface class SessionApi {
  Future<Map<String, dynamic>> createSession({
    required String patientId,
    required String preferredHand,
    required String notes,
  });

  Future<Map<String, dynamic>?> activeSession();

  Future<Map<String, dynamic>?> recoveredSession();

  Future<Map<String, dynamic>> endSession(String sessionId);

  Future<Map<String, dynamic>> addEvent({
    required String sessionId,
    required String label,
    required String category,
    required String note,
  });

  Uri summaryDownloadUri(String sessionId);

  Uri rawDownloadUri(String sessionId);

  void close();
}

class SessionApiException implements Exception {
  final String message;
  final int? statusCode;

  const SessionApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class HttpSessionApi implements SessionApi {
  final Uri baseUri;
  final http.Client _client;

  HttpSessionApi({required this.baseUri, http.Client? client})
    : _client = client ?? http.Client();

  @override
  Future<Map<String, dynamic>> createSession({
    required String patientId,
    required String preferredHand,
    required String notes,
  }) async {
    return _requestMap(
      'POST',
      '/api/sessions',
      body: {
        'patient_id': patientId,
        'preferred_hand': preferredHand,
        'notes': notes,
      },
    );
  }

  @override
  Future<Map<String, dynamic>?> activeSession() async {
    final value = await _request('GET', '/api/sessions/active');
    if (value == null) return null;
    return _asMap(value);
  }

  @override
  Future<Map<String, dynamic>?> recoveredSession() async {
    final value = await _request('GET', '/api/sessions/recovered');
    if (value == null) return null;
    return _asMap(value);
  }

  @override
  Future<Map<String, dynamic>> endSession(String sessionId) {
    return _requestMap('POST', '/api/sessions/$sessionId/end');
  }

  @override
  Future<Map<String, dynamic>> addEvent({
    required String sessionId,
    required String label,
    required String category,
    required String note,
  }) {
    return _requestMap(
      'POST',
      '/api/sessions/$sessionId/events',
      body: {'label': label, 'category': category, 'note': note},
    );
  }

  @override
  Uri summaryDownloadUri(String sessionId) {
    return _uri('/api/sessions/$sessionId/download/summary');
  }

  @override
  Uri rawDownloadUri(String sessionId) {
    return _uri('/api/sessions/$sessionId/download/raw');
  }

  Future<Map<String, dynamic>> _requestMap(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return _asMap(await _request(method, path, body: body));
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(method, _uri(path));
    request.headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = json.encode(body);
    }

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (error) {
      throw SessionApiException('Brak połączenia z serwerem: $error');
    }
    final responseBody = await response.stream.bytesToString();
    dynamic decoded;
    if (responseBody.isNotEmpty) {
      try {
        decoded = json.decode(responseBody);
      } catch (_) {
        decoded = null;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map ? decoded['detail'] : null;
      throw SessionApiException(
        detail is String ? detail : 'Błąd serwera (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is! Map) {
      throw const SessionApiException(
        'Serwer zwrócił nieprawidłowe dane sesji',
      );
    }
    return Map<String, dynamic>.from(value);
  }

  Uri _uri(String path) => baseUri.replace(path: path, query: null);

  @override
  void close() {
    _client.close();
  }
}
