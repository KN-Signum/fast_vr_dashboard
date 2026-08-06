import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/backend_url.dart';

typedef VrSimulationChannelFactory =
    VrSimulationConnection Function(String url);

abstract interface class VrSimulationConnection {
  Stream<dynamic> get stream;
  Future<void> get ready;
  void add(String message);
  Future<void> close();
}

class WebSocketVrSimulationConnection implements VrSimulationConnection {
  WebSocketVrSimulationConnection(String url)
    : _channel = WebSocketChannel.connect(Uri.parse(url));

  final WebSocketChannel _channel;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  Future<void> get ready => _channel.ready;

  @override
  void add(String message) => _channel.sink.add(message);

  @override
  Future<void> close() => _channel.sink.close();
}

class VrSimulationEngine {
  static const visibleBirdCount = 8;
  static const visibleBirdCountLeft = 4;
  static const visibleBirdCountRight = 4;

  static const Map<String, List<Map<String, String>>> screenActions = {
    'info': [
      {'action': 'next_to_selection', 'label': 'Zacznij badanie'},
    ],
    'menu': [
      {'action': 'start_forest', 'label': 'Spacer w lesie'},
      {'action': 'start_painting', 'label': 'Malowanie'},
      {'action': 'exit_app', 'label': 'Wyjdź'},
    ],
    'forest': [
      {'action': 'back_to_menu', 'label': 'Wyjdź do menu'},
      {'action': 'pause_walk', 'label': 'Pauza'},
      {'action': 'resume_walk', 'label': 'Wznów spacer'},
    ],
    'painting': [
      {'action': 'move_easel_left', 'label': 'Sztaluga w lewo'},
      {'action': 'move_easel_right', 'label': 'Sztaluga w prawo'},
      {'action': 'move_easel_up', 'label': 'Podnieś sztalugę'},
      {'action': 'move_easel_down', 'label': 'Obniż sztalugę'},
      {'action': 'clear_palette', 'label': 'Wyczyść paletę'},
      {'action': 'save_painting', 'label': 'Zapisz obraz'},
      {'action': 'next_image', 'label': 'Następny wzór'},
      {'action': 'back_to_menu', 'label': 'Wyjdź do menu'},
    ],
  };

  static const _mockJpegBase64 =
      '/9j/4AAQSkZJRgABAQABLAEsAAD/4QCMRXhpZgAATU0AKgAAAAgABQESAAMAAAABAAEAAAEaAAUAAAABAAAASgEbAAUAAAABAAAAUgEoAAMAAAABAAIAAIdpAAQAAAABAAAAWgAAAAAAAAEsAAAAAQAAASwAAAABAAOgAQADAAAAAQABAACgAgAEAAAAAQAAABCgAwAEAAAAAQAAABAAAAAA/+0AOFBob3Rvc2hvcCAzLjAAOEJJTQQEAAAAAAAAOEJJTQQlAAAAAAAQ1B2M2Y8AsgTpgAmY7PhCfv/AABEIABAAEAMBIgACEQEDEQH/xAAfAAABBQEBAQEBAQAAAAAAAAAAAQIDBAUGBwgJCgv/xAC1EAACAQMDAgQDBQUEBAAAAX0BAgMABBEFEiExQQYTUWEHInEUMoGRoQgjQrHBFVLR8CQzYnKCCQoWFxgZGiUmJygpKjQ1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4eLj5OXm5+jp6vHy8/T19vf4+fr/xAAfAQADAQEBAQEBAQEBAAAAAAAAAQIDBAUGBwgJCgv/xAC1EQACAQIEBAMEBwUEBAABAncAAQIDEQQFITEGEkFRB2FxEyIygQgUQpGhscEJIzNS8BVictEKFiQ04SXxFxgZGiYnKCkqNTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqCg4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2dri4+Tl5ufo6ery8/T19vf4+fr/2wBDAAICAgICAgMCAgMFAwMDBQYFBQUFBggGBgYGBggKCAgICAgICgoKCgoKCgoMDAwMDAwODg4ODg8PDw8PDw8PDw//2wBDAQICAgQEBAcEBAcQCwkLEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBD/3QAEAAH/2gAMAwEAAhEDEQA/AP2+8e+PbDwTYxgRm91W9Pl2dlHzJNIeBwMkKCeTj2GSQKm8CN4ok0oy+ML+3utSkO54bZFVLYHOIztLFmHck4zwPUv8beEf+En0u5/syddM1wW8sNnqCxq01v5uN21iMqGxhipDAcqQcGvNP2ctC8e+GfAzaH8SPDVhoGt287+bNpt0LqC/BPy3BYqkiuRwysuBxtOPlX6FfVv7Obg17S6ve1+u3aPe123vZWv8uoY7+1bzX7nl0s7JPzW8pebtGKta8m7f/9k=';

  String currentScreen = 'info';
  String? lastCommand;
  List<Map<String, dynamic>> lastResponses = const [];
  String? noResponseMessage;

  List<Map<String, dynamic>> processCommand(Map<String, dynamic> message) {
    if (message['type'] != 'command' || message['action'] is! String) {
      return const [];
    }

    final action = message['action'] as String;
    lastCommand = action;
    noResponseMessage = null;

    switch (action) {
      case 'request_state':
        return _setResponses(_currentStateResponses());
      case 'next_to_selection':
        currentScreen = 'menu';
        return _setResponses([_stateUpdate()]);
      case 'start_forest':
        currentScreen = 'forest';
        return _setResponses(_currentStateResponses());
      case 'start_painting':
        currentScreen = 'painting';
        return _setResponses([_stateUpdate()]);
      case 'back_to_menu':
        currentScreen = 'info';
        return _setResponses([_stateUpdate()]);
      case 'save_painting':
        return _setResponses([
          {
            'type': 'canvas_image',
            'image_base64': _mockJpegBase64,
            'format': 'jpg',
          },
        ]);
      case 'exit_app':
      case 'clear_palette':
      case 'next_image':
      case 'move_easel_left':
      case 'move_easel_right':
      case 'move_easel_up':
      case 'move_easel_down':
      case 'start_walk':
      case 'pause_walk':
      case 'resume_walk':
        return _withoutResponse(
          'Unity nie wysyła wiadomości zwrotnej dla tej akcji.',
        );
      default:
        return _withoutResponse('Nieznana komenda symulatora VR.');
    }
  }

  List<Map<String, dynamic>> initialResponses() {
    lastCommand = null;
    noResponseMessage = null;
    return _setResponses([_stateUpdate()]);
  }

  Map<String, dynamic> _stateUpdate() => {
    'type': 'state_update',
    'current_view': currentScreen,
    'available_actions': screenActions[currentScreen] ?? const [],
  };

  List<Map<String, dynamic>> _currentStateResponses() => [
    _stateUpdate(),
    if (currentScreen == 'forest')
      {
        'type': 'bird_count',
        'visible': visibleBirdCount,
        'left': visibleBirdCountLeft,
        'right': visibleBirdCountRight,
      },
  ];

  List<Map<String, dynamic>> _setResponses(
    List<Map<String, dynamic>> responses,
  ) {
    lastResponses = List.unmodifiable(responses);
    return responses;
  }

  List<Map<String, dynamic>> _withoutResponse(String message) {
    lastResponses = const [];
    noResponseMessage = message;
    return const [];
  }
}

class VrSimulationProvider with ChangeNotifier {
  VrSimulationProvider({VrSimulationChannelFactory? channelFactory})
    : _channelFactory = channelFactory ?? WebSocketVrSimulationConnection.new;

  final VrSimulationChannelFactory _channelFactory;
  VrSimulationEngine _engine = VrSimulationEngine();
  VrSimulationConnection? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool _enabled = false;
  bool _connected = false;
  bool _connecting = false;
  String? _error;

  bool get enabled => _enabled;
  bool get connected => _connected;
  bool get connecting => _connecting;
  String? get error => _error;
  String get currentScreen => _engine.currentScreen;
  String? get lastCommand => _engine.lastCommand;
  List<Map<String, dynamic>> get lastResponses => _engine.lastResponses;
  String? get noResponseMessage => _engine.noResponseMessage;

  static String defaultBackendUrl([Uri? baseUri]) {
    return resolveBackendWebSocketUrl(
      baseUri ?? Uri.base,
      useDevelopmentBackend: kDebugMode,
      role: 'vr_simulator',
    );
  }

  Future<void> enable([String? url]) async {
    if (_enabled && (_connected || _connecting)) return;

    disable(notify: false);
    _enabled = true;
    _connecting = true;
    _error = null;
    _engine = VrSimulationEngine();
    notifyListeners();

    try {
      final channel = _channelFactory(url ?? defaultBackendUrl());
      _channel = channel;
      _subscription = channel.stream.listen(
        _handleMessage,
        onDone: () => _handleConnectionClosed(channel),
        onError: (Object error) => _handleConnectionError(channel, error),
        cancelOnError: true,
      );
      await channel.ready;
      if (!_enabled || !identical(_channel, channel)) return;

      _connecting = false;
      _connected = true;
      _sendResponses(_engine.initialResponses());
      notifyListeners();
    } catch (error) {
      _handleConnectionError(_channel, error);
    }
  }

  void disable({bool notify = true}) {
    final channel = _channel;
    _enabled = false;
    _connected = false;
    _connecting = false;
    _error = null;
    _channel = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    if (channel != null) unawaited(channel.close());
    if (notify) notifyListeners();
  }

  void _handleMessage(dynamic event) {
    if (!_enabled || event is! String) return;

    try {
      final decoded = json.decode(event);
      if (decoded is! Map<String, dynamic>) return;
      final responses = _engine.processCommand(decoded);
      _sendResponses(responses);
      notifyListeners();
    } catch (error) {
      _error = 'Nieprawidłowa wiadomość WebSocket: $error';
      notifyListeners();
    }
  }

  void _sendResponses(List<Map<String, dynamic>> responses) {
    if (!_connected || _channel == null) return;
    for (final response in responses) {
      _channel!.add(json.encode(response));
    }
  }

  void _handleConnectionClosed(VrSimulationConnection channel) {
    if (!identical(_channel, channel) || !_enabled) return;
    _connected = false;
    _connecting = false;
    _error = 'Połączenie symulatora VR zostało zamknięte.';
    notifyListeners();
  }

  void _handleConnectionError(VrSimulationConnection? channel, Object error) {
    if (channel != null && !identical(_channel, channel)) return;
    _connected = false;
    _connecting = false;
    _error = 'Nie udało się uruchomić symulatora VR: $error';
    notifyListeners();
  }

  @override
  void dispose() {
    disable(notify: false);
    super.dispose();
  }
}
