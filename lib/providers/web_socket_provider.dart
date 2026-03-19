import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketProvider with ChangeNotifier {
  WebSocketChannel? _channel;
  String _status = 'Kliknij "Szukaj gogli" aby rozpocząć';
  Uint8List? _lastFrame;
  int _frameCount = 0;

  WebSocketChannel? get channel => _channel;
  String get status => _status;
  Uint8List? get lastFrame => _lastFrame;
  int get frameCount => _frameCount;

  void connect(String url) {
    try {
      print('🔗 Łączenie się z: $url');
      final ch = HtmlWebSocketChannel.connect(url);
      ch.innerWebSocket.binaryType = 'arraybuffer';
      print('✅ Kanał WebSocket utworzony');

      ch.stream.listen(
        (event) {
          print('📡 Otrzymano event: ${event.runtimeType}');
          if (event is Uint8List) {
            _lastFrame = event;
            _status = 'Połączony (${event.length} B)';
          } else if (event is ByteBuffer) {
            _lastFrame = Uint8List.view(event);
            _status = 'Połączony (${event.lengthInBytes} B)';
          } else if (event is List<int>) {
            _lastFrame = Uint8List.fromList(event);
            _status = 'Połączony (${event.length} B)';
          } else if (event is String) {
            _handleTextMessage(event);
          } else {
            print('❓ Nieznany typ eventu: ${event.runtimeType}');
          }
          notifyListeners();
        },
        onDone: () {
          print('🔌 Stream zakończony');
          _status = 'Rozłączony';
          _channel = null;
          notifyListeners();
        },
        onError: (e) {
          print('❌ Błąd streamu: $e');
          _status = 'Błąd połączenia: $e';
          _channel = null;
          notifyListeners();
        },
      );

      print('✅ Stream listener dodany');
      _channel = ch;
      _status = 'Połączony';
      notifyListeners();
    } catch (e) {
      print('❌ Wyjątek w _connect: $e');
      _status = 'Wyjątek: $e';
      notifyListeners();
    }
  }

  void _handleTextMessage(String message) {
    // This will be handled by other providers listening to the stream
    // For now, we just decode and pass it on.
    try {
      final data = json.decode(message);
      // Here you would notify other listeners/providers with the data
    } catch (e) {
      print('❌ Błąd parsowania JSON lub nieznany format wiadomości: $e');
    }
  }

  void sendMessage(Map<String, dynamic> message) {
    if (_channel == null) {
      print('❌ Brak połączenia WebSocket');
      return;
    }

    try {
      final jsonString = json.encode(message);
      _channel!.sink.add(jsonString);
      print('📤 Wysłano: $jsonString');
    } catch (e) {
      print('❌ Błąd wysyłania wiadomości: $e');
    }
  }

  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }
}
