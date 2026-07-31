import 'dart:convert';

import 'package:http/http.dart' as http;

abstract interface class EegControlApi {
  Future<Map<String, dynamic>> state();

  Future<Map<String, dynamic>> setEnabled(bool enabled);

  void close();
}

class EegControlApiException implements Exception {
  final String message;

  const EegControlApiException(this.message);

  @override
  String toString() => message;
}

class HttpEegControlApi implements EegControlApi {
  final Uri baseUri;
  final http.Client _client;

  HttpEegControlApi({required this.baseUri, http.Client? client})
    : _client = client ?? http.Client();

  @override
  Future<Map<String, dynamic>> state() => _request('GET', '/api/health');

  @override
  Future<Map<String, dynamic>> setEnabled(bool enabled) {
    return _request('PUT', '/api/eeg', body: {'enabled': enabled});
  }

  Future<Map<String, dynamic>> _request(
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
      throw EegControlApiException('Brak połączenia z serwerem: $error');
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
      throw EegControlApiException(
        detail is String ? detail : 'Błąd serwera (${response.statusCode})',
      );
    }
    if (decoded is! Map) {
      throw const EegControlApiException(
        'Serwer zwrócił nieprawidłowy stan EEG',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  Uri _uri(String path) => baseUri.replace(path: path, query: null);

  @override
  void close() => _client.close();
}
