import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// Callback for eye tracking data
typedef OnEyeTrackingData = void Function(Map<String, dynamic> data);
// Callback for EEG data
typedef OnEegData = void Function(Map<String, dynamic> data);

class WebSocketProvider with ChangeNotifier {
  WebSocketChannel? _channel;
  StreamController<dynamic> _streamController = StreamController.broadcast();
  Stream<dynamic> get stream => _streamController.stream;
  String _status = 'Połącz z backendem, aby rozpocząć';
  Uint8List? _lastFrame;
  DateTime? _lastFrameAt;
  DateTime? _lastVrMessageAt;
  bool _isConnected = false;
  OnEyeTrackingData? _onEyeTrackingData;
  OnEegData? _onEegData;

  WebSocketChannel? get channel => _channel;
  String get status => _status;
  Uint8List? get lastFrame => _lastFrame;
  DateTime? get lastFrameAt => _lastFrameAt;
  DateTime? get lastVrMessageAt => _lastVrMessageAt;
  bool get isConnected => _isConnected;

  static String defaultBackendUrl() {
    final base = Uri.base;
    if (base.scheme != 'http' && base.scheme != 'https') {
      return 'ws://127.0.0.1:8080/ws';
    }

    final host = base.host.isEmpty ? '127.0.0.1' : base.host;
    final isLocalHost =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final port = isLocalHost && base.hasPort && base.port != 8080
        ? 8080
        : (base.hasPort ? base.port : null);

    return Uri(scheme: scheme, host: host, port: port, path: '/ws').toString();
  }

  /// Register callback for eye tracking data
  void setEyeTrackingCallback(OnEyeTrackingData callback) {
    _onEyeTrackingData = callback;
  }

  /// Register callback for EEG data
  void setEegCallback(OnEegData callback) {
    _onEegData = callback;
  }

  void connect(String url) {
    if (_isConnected) {
      debugPrint('ℹ️ Już połączony.');
      return;
    }
    try {
      debugPrint('🔗 Łączenie się z: $url');
      _status = 'Łączenie...';
      notifyListeners();

      final ch = HtmlWebSocketChannel.connect(url);
      ch.innerWebSocket.binaryType = 'arraybuffer';
      _channel = ch;
      _isConnected = true;
      _status = 'Połączony';

      sendMessage({"type": "command", "action": "request_state"});

      debugPrint('📡 Wysłano zapytanie o stan sceny...');
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
            debugPrint('❓ Nieznany typ eventu: ${event.runtimeType}');
          }
        },
        onDone: () {
          debugPrint('🔌 Stream zakończony');
          _status = 'Rozłączony';
          _channel = null;
          _isConnected = false;
          _lastFrameAt = null;
          _lastVrMessageAt = null;
          _streamController.close();
          _streamController =
              StreamController.broadcast(); // Re-create for next connection
          notifyListeners();
        },
        onError: (e) {
          debugPrint('❌ Błąd streamu: $e');
          _status = 'Błąd połączenia: $e';
          _channel = null;
          _isConnected = false;
          _lastFrameAt = null;
          _lastVrMessageAt = null;
          _streamController.close();
          _streamController =
              StreamController.broadcast(); // Re-create for next connection
          notifyListeners();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('❌ Wyjątek w _connect: $e');
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
      _lastFrameAt = DateTime.now();

      _status = 'Otrzymano klatkę JPEG (${_lastFrame!.lengthInBytes} B)';
      notifyListeners(); // To odpali Selector w Viewere i odświeży obraz
    } else {
      debugPrint('❓ Otrzymano nieznany pakiet binarny (prefix: ${data[0]})');
    }
  }

  void _handleTextMessage(String message) {
    try {
      final data = json.decode(message) as Map<String, dynamic>;
      final type = data['type'] as String?;

      debugPrint('📩 WS JSON received: $type');

      // Handle eye tracking data separately
      if (type == 'eye_tracking') {
        debugPrint('👁️ Forwarding eye_tracking to EyeTrackingProvider');
        _onEyeTrackingData?.call(data);
        return;
      }

      // Handle EEG data separately
      if (type == 'eeg_data') {
        debugPrint('🧠 Forwarding eeg_data to EegProvider');
        _onEegData?.call(data);
        return;
      }

      _lastVrMessageAt = DateTime.now();
      _status = 'Otrzymano dane JSON: ${type ?? 'nieznany'}';
      debugPrint('✅ Otrzymano JSON: ${data.keys.first}...');
    } catch (e) {
      debugPrint('❌ Błąd parsowania JSON: $e');
      _status = 'Błąd danych JSON';
    }
    notifyListeners();
  }

  void sendMessage(Map<String, dynamic> message) {
    if (!_isConnected || _channel == null) {
      debugPrint('❌ Brak połączenia WebSocket, nie można wysłać wiadomości.');
      return;
    }

    try {
      final jsonString = json.encode(message);
      _channel!.sink.add(jsonString);
      debugPrint('📤 Wysłano: $jsonString');
    } catch (e) {
      debugPrint('❌ Błąd wysyłania wiadomości: $e');
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
    _lastFrameAt = null;
    _lastVrMessageAt = null;
    notifyListeners();
    debugPrint('🔌 Rozłączono manualnie.');
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
