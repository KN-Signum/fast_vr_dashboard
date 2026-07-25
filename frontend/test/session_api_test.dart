import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vr_fast_dashboard/services/session_api.dart';

void main() {
  test('creates a session using backend JSON fields', () async {
    late http.Request captured;
    final api = HttpSessionApi(
      baseUri: Uri.parse('http://localhost:8080'),
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          json.encode({
            'session_id': 'session-001',
            'patient_id': 'patient-001',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final session = await api.createSession(
      patientId: 'patient-001',
      preferredHand: 'left',
      notes: 'Baseline',
    );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/sessions');
    expect(json.decode(captured.body), {
      'patient_id': 'patient-001',
      'preferred_hand': 'left',
      'notes': 'Baseline',
    });
    expect(session['session_id'], 'session-001');
  });

  test('surfaces backend error details', () async {
    final api = HttpSessionApi(
      baseUri: Uri.parse('http://localhost:8080'),
      client: MockClient(
        (_) async => http.Response(
          json.encode({'detail': 'Another session is active'}),
          409,
        ),
      ),
    );

    expect(
      () => api.createSession(
        patientId: 'patient-001',
        preferredHand: 'left',
        notes: '',
      ),
      throwsA(
        isA<SessionApiException>().having(
          (error) => error.message,
          'message',
          'Another session is active',
        ),
      ),
    );
  });
}
