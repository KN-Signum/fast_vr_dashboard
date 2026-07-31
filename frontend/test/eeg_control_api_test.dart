import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vr_fast_dashboard/services/eeg_control_api.dart';

void main() {
  test('sends EEG enabled state to backend', () async {
    late http.Request captured;
    final api = HttpEegControlApi(
      baseUri: Uri.parse('http://localhost:8080'),
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          json.encode({
            'eeg_enabled': false,
            'eeg_mode': 'real',
            'eeg_status': 'disabled',
          }),
          200,
        );
      }),
    );

    final result = await api.setEnabled(false);

    expect(captured.method, 'PUT');
    expect(captured.url.path, '/api/eeg');
    expect(json.decode(captured.body), {'enabled': false});
    expect(result['eeg_enabled'], isFalse);
    api.close();
  });

  test('surfaces EEG control errors from backend', () async {
    final api = HttpEegControlApi(
      baseUri: Uri.parse('http://localhost:8080'),
      client: MockClient(
        (_) async =>
            http.Response(json.encode({'detail': 'Sesja jest aktywna'}), 409),
      ),
    );

    expect(
      () => api.setEnabled(false),
      throwsA(
        isA<EegControlApiException>().having(
          (error) => error.message,
          'message',
          'Sesja jest aktywna',
        ),
      ),
    );
    api.close();
  });
}
