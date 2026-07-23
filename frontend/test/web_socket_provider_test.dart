import 'package:flutter_test/flutter_test.dart';
import 'package:vr_fast_dashboard/utils/backend_url.dart';

void main() {
  group('resolveBackendWebSocketUrl', () {
    test('preserves the host and custom port used to serve the dashboard', () {
      final url = resolveBackendWebSocketUrl(
        Uri.parse('http://localhost:5173/session'),
      );

      expect(url, 'ws://localhost:5173/ws?role=dashboard');
    });

    test('uses the local backend while running from Flutter development', () {
      final url = resolveBackendWebSocketUrl(
        Uri.parse('http://localhost:5173/session'),
        useDevelopmentBackend: true,
      );

      expect(url, 'ws://127.0.0.1:8080/ws?role=dashboard');
    });

    test('uses a secure websocket for an HTTPS dashboard', () {
      final url = resolveBackendWebSocketUrl(
        Uri.parse('https://dashboard.example.com/app'),
      );

      expect(url, 'wss://dashboard.example.com/ws?role=dashboard');
    });

    test('falls back to the development backend outside HTTP contexts', () {
      final url = resolveBackendWebSocketUrl(
        Uri.parse('file:///tmp/index.html'),
      );

      expect(url, 'ws://127.0.0.1:8080/ws?role=dashboard');
    });
  });
}
