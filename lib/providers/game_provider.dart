import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:html' as html;

class GameProvider with ChangeNotifier {
  String _currentScreen = 'info'; // info, menu, game
  List<Map<String, dynamic>> _gameActions = [];
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  Uint8List? _lastFrame;

  String get currentScreen => _currentScreen;
  List<Map<String, dynamic>> get gameActions => _gameActions;
  GlobalKey<ScaffoldMessengerState> get scaffoldMessengerKey =>
      _scaffoldMessengerKey;

  void handleMessage(String message, Uint8List? lastFrame) {
    _lastFrame = lastFrame;
    try {
      final data = json.decode(message);

      if (data is Map<String, dynamic>) {
        final type = data['type'];

        switch (type) {
          case 'frame':
            // This is handled by WebSocketProvider now
            break;
          case 'game_started':
            print('🎮 Gra rozpoczęta');
            final actions = data['actions'] as List<dynamic>?;
            final gameName = data['game'] as String?;
            _currentScreen = 'game';
            _gameActions = actions?.cast<Map<String, dynamic>>() ?? [];
            print('🎮 Rozpoczęto grę: $gameName');
            print('🎮 Dostępne akcje: $_gameActions');
            notifyListeners();
            break;
          case 'available_games':
            print('🎮 Dostępne gry: ${data['games']}');
            _currentScreen = 'menu';
            notifyListeners();
            break;
          case 'canvas_image':
            print('🖼️ Otrzymano obraz do zapisania (canvas_image)');
            _downloadCanvasImage(data);
            break;
          case 'action_completed':
            print('✅ Akcja zakończona sukcesem: ${data['action']}');

            if (data.containsKey('image_base64')) {
              print('🖼️ Znaleziono dane obrazu w potwierdzeniu akcji');
              _downloadCanvasImage(data);
            } else if (data['action'] == 'save_canvas' && _lastFrame != null) {
              print('🖼️ Zapisywanie aktualnej klatki jako wynik save_canvas');
              _downloadCanvasImage({
                'image_base64': base64.encode(_lastFrame!),
                'format': 'jpg',
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              });
            }

            if (scaffoldMessengerKey.currentState != null) {
              scaffoldMessengerKey.currentState?.showSnackBar(
                SnackBar(content: Text('Akcja wykonana: ${data['action']}')),
              );
            }
            break;
          case 'menu_state':
            final screen = data['screen'] as String?;
            print('📱 Stan menu: $screen');
            if (screen == 'game') {
              _currentScreen = 'game';
            } else {
              _currentScreen = 'menu';
            }
            notifyListeners();
            break;
          default:
            print('❓ Nieznany typ wiadomości: $type');
        }
      }
    } catch (e) {
      final trimmed = message.trim();
      print('ℹ️ Otrzymano nie-JSON tekst: ${trimmed.length} zn.');

      if (trimmed.startsWith('data:image')) {
        final parts = trimmed.split(',');
        final base64Part = parts.length > 1
            ? parts.sublist(1).join(',')
            : parts[0];
        print('🖼️ Rozpoznano data-URI obrazu, zapisuję...');
        _downloadCanvasImage({
          'image_base64': base64Part,
          'format': 'png',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        return;
      }

      final candidate = trimmed.replaceAll(RegExp(r'\s+'), '');
      final base64Pattern = RegExp(r'^[A-Za-z0-9+/=]+$');
      if (candidate.length > 200 && base64Pattern.hasMatch(candidate)) {
        print(
          '🖼️ Rozpoznano prawdopodobny base64 obrazu, zapisuję jako png...',
        );
        _downloadCanvasImage({
          'image_base64': candidate,
          'format': 'png',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        return;
      }

      print('❌ Błąd parsowania JSON lub nieznany format wiadomości: $e');
    }
  }

  void _downloadCanvasImage(Map<String, dynamic> data) {
    try {
      final base64Image = data['image_base64'] as String?;
      final format = data['format'] as String? ?? 'png';
      final timestamp = data['timestamp'] as num?;

      if (base64Image == null || base64Image.isEmpty) {
        print('❌ Brak danych obrazu');
        return;
      }

      final fileName =
          'canvas_${timestamp?.toInt() ?? DateTime.now().millisecondsSinceEpoch}.$format';

      final bytes = base64.decode(base64Image);

      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();

      html.Url.revokeObjectUrl(url);

      print('✅ Obraz zapisany: $fileName');

      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Obraz zapisany: $fileName')),
      );
    } catch (e) {
      print('❌ Błąd zapisywania obrazu: $e');
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Błąd zapisywania obrazu')),
      );
    }
  }

  void setCurrentScreen(String screen) {
    _currentScreen = screen;
    notifyListeners();
  }
}
