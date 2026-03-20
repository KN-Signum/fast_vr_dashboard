import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'dart:js_interop';

class GameProvider with ChangeNotifier {
  // Stan ekranu: 'info', 'menu', 'forest', 'painting'
  String _currentScreen = 'info';

  // Lista akcji: Teraz używamy Map, żeby trzymać też etykiety przycisków
  List<Map<String, dynamic>> _gameActions = [];

  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  Uint8List? _lastFrame;

  Uint8List? get lastFrame => _lastFrame;
  String get currentScreen => _currentScreen;
  List<Map<String, dynamic>> get gameActions => _gameActions;
  GlobalKey<ScaffoldMessengerState> get scaffoldMessengerKey =>
      _scaffoldMessengerKey;

  // Wywoływane przez WebSocketProvider dla obrazu
  void updateFrame(Uint8List frame) {
    _lastFrame = frame;
    notifyListeners();
  }

  // Główny mózg odbierania komunikatów JSON
  void handleMessage(String message, Uint8List? frame) {
    _lastFrame = frame;
    try {
      final data = json.decode(message);

      if (data is Map<String, dynamic>) {
        final type = data['type'];

        switch (type) {
          // --- NOWY KLUCZOWY CASE: Synchronizacja stanu z Unity ---
          case 'state_update':
            _currentScreen = data['current_view'] ?? 'menu';
            // Przyjmujemy listę akcji z Unity, np. [{"action": "clear_palette", "label": "Wyczyść"}]
            if (data.containsKey('available_actions')) {
              _gameActions = List<Map<String, dynamic>>.from(
                data['available_actions'],
              );
            }
            print(
              '📱 Zmiana widoku na: $_currentScreen. Dostępne akcje: ${_gameActions.length}',
            );
            notifyListeners();
            break;

          // Obsługa pobierania obrazu (Twoja stara logika - zostawiamy!)
          case 'canvas_image':
            _downloadCanvasImage(data);
            break;

          case 'action_completed':
            _handleActionCompleted(data);
            break;

          default:
            print('❓ Inny typ wiadomości: $type');
        }
      }
    } catch (e) {
      _handleNonJsonFallback(message); // Logika Base64, którą miałeś wcześniej
    }
  }

  // --- LOGIKA POMOCNICZA (Twoje stare funkcje) ---

  void _handleActionCompleted(Map<String, dynamic> data) {
    print('✅ Akcja zakończona: ${data['action']}');
    if (data.containsKey('image_base64')) {
      _downloadCanvasImage(data);
    }
    if (scaffoldMessengerKey.currentState != null) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Wykonano: ${data['action']}')),
      );
    }
  }

  void _handleNonJsonFallback(String message) {
    final trimmed = message.trim();
    if (trimmed.startsWith('data:image') || trimmed.length > 500) {
      print('🖼️ Wykryto surowy Base64 obrazu, próbuję zapisać...');
      // ... (tu kod Base64, który miałeś)
    }
  }

  void _downloadCanvasImage(Map<String, dynamic> data) {
    try {
      final base64Image = data['image_base64'] as String?;
      final format = data['format'] as String? ?? 'png';
      if (base64Image == null || base64Image.isEmpty) return;

      final bytes = base64.decode(base64Image);
      final blob = web.Blob([bytes.toJS].toJS);
      final url = web.URL.createObjectURL(blob);
      final anchor = web.document.createElement('a') as web.HTMLAnchorElement;

      anchor.href = url;
      anchor.download =
          'wynik_badania_${DateTime.now().millisecondsSinceEpoch}.$format';
      anchor.click();
      web.URL.revokeObjectURL(url);
    } catch (e) {
      print('❌ Błąd zapisu: $e');
    }
  }

  void setCurrentScreen(String screen) {
    _currentScreen = screen;
    notifyListeners();
  }
}
