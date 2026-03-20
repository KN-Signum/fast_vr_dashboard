import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketProvider with ChangeNotifier {
  WebSocketChannel? _channel;
  StreamController<dynamic> _streamController = StreamController.broadcast();
  Stream<dynamic> get stream => _streamController.stream;
  String _status = 'Kliknij "Szukaj gogli" aby rozpocząć';
  Uint8List? _lastFrame;
  Map<String, dynamic>? _lastJsonMessage;
  bool _isConnected = false;

  WebSocketChannel? get channel => _channel;
  String get status => _status;
  Uint8List? get lastFrame => _lastFrame;
  Map<String, dynamic>? get lastJsonMessage => _lastJsonMessage;
  bool get isConnected => _isConnected;

  void connect(String url) {
    if (_isConnected) {
      print('ℹ️ Już połączony.');
      return;
    }
    try {
      print('🔗 Łączenie się z: $url');
      _status = 'Łączenie...';
      notifyListeners();

      final ch = HtmlWebSocketChannel.connect(url);
      ch.innerWebSocket.binaryType = 'arraybuffer';
      _channel = ch;
      _isConnected = true;
      _status = 'Połączony';

      sendMessage({"type": "command", "action": "request_state"});

      print('📡 Wysłano zapytanie o stan sceny...');
      notifyListeners();

      ch.stream.listen(
        (event) {
          _streamController.add(
            event,
          ); // Forward events to our broadcast stream
          if (event is Uint8List) {
            _handleBinaryMessage(event);
          } else if (event is String) {
            _handleTextMessage(event);
          } else {
            print('❓ Nieznany typ eventu: ${event.runtimeType}');
          }
        },
        onDone: () {
          print('🔌 Stream zakończony');
          _status = 'Rozłączony';
          _channel = null;
          _isConnected = false;
          _streamController.close();
          _streamController =
              StreamController.broadcast(); // Re-create for next connection
          notifyListeners();
        },
        onError: (e) {
          print('❌ Błąd streamu: $e');
          _status = 'Błąd połączenia: $e';
          _channel = null;
          _isConnected = false;
          _streamController.close();
          _streamController =
              StreamController.broadcast(); // Re-create for next connection
          notifyListeners();
        },
        cancelOnError: true,
      );
    } catch (e) {
      print('❌ Wyjątek w _connect: $e');
      _status = 'Wyjątek: $e';
      _isConnected = false;
      notifyListeners();
    }
  }

  void _handleBinaryMessage(Uint8List data) {
    if (data.isEmpty) return;

    // 255 (0xFF) to początek standardowego pliku JPEG
    // 1 to Twój niestandardowy prefix z poprzedniej wersji skryptu
    if (data[0] == 255 || data[0] == 1) {
      // Jeśli prefix to 1, odcinamy go. Jeśli 255, bierzemy całość (bo to już start JPG)
      _lastFrame = (data[0] == 1) ? data.sublist(1) : data;

      _status = 'Otrzymano klatkę JPEG (${_lastFrame!.lengthInBytes} B)';
      notifyListeners(); // To odpali Selector w Viewere i odświeży obraz
    } else {
      print('❓ Otrzymano nieznany pakiet binarny (prefix: ${data[0]})');
    }
  }

  void _handleTextMessage(String message) {
    try {
      final data = json.decode(message) as Map<String, dynamic>;
      _lastJsonMessage = data;
      _status = 'Otrzymano dane JSON: ${data['type'] ?? 'nieznany'}';
      print('✅ Otrzymano JSON: $data');
    } catch (e) {
      print('❌ Błąd parsowania JSON: $e');
      _status = 'Błąd danych JSON';
    }
    notifyListeners();
  }

  void sendMessage(Map<String, dynamic> message) {
    if (!_isConnected || _channel == null) {
      print('❌ Brak połączenia WebSocket, nie można wysłać wiadomości.');
      return;
    }

    try {
      final jsonString = json.encode(message);
      _channel!.sink.add(jsonString);
      print('📤 Wysłano: $jsonString');
    } catch (e) {
      print('❌ Błąd wysyłania wiadomości: $e');
      _status = 'Błąd wysyłania';
      notifyListeners();
    }
  }

  void disconnect() {
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
    }
    if (!_streamController.isClosed) {
      _streamController.close();
      _streamController = StreamController.broadcast();
    }
    _isConnected = false;
    _status = 'Rozłączony';
    _lastFrame = null;
    notifyListeners();
    print('🔌 Rozłączono manualnie.');
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
