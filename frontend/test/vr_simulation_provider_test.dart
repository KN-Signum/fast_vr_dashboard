import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vr_fast_dashboard/providers/vr_simulation_provider.dart';

void main() {
  group('VrSimulationEngine', () {
    test('matches the Unity screen action lists', () {
      expect(_actionsFor('info'), ['next_to_selection']);
      expect(_actionsFor('menu'), [
        'start_forest',
        'start_painting',
        'exit_app',
      ]);
      expect(_actionsFor('forest'), [
        'back_to_menu',
        'pause_walk',
        'resume_walk',
      ]);
      expect(_actionsFor('painting'), [
        'move_easel_left',
        'move_easel_right',
        'move_easel_up',
        'move_easel_down',
        'clear_palette',
        'save_painting',
        'next_image',
        'back_to_menu',
      ]);
    });

    test('moves through screens and reports the forest bird count', () {
      final engine = VrSimulationEngine();

      var responses = engine.processCommand(_command('next_to_selection'));
      expect(engine.currentScreen, 'menu');
      expect(responses.single['current_view'], 'menu');

      responses = engine.processCommand(_command('start_forest'));
      expect(engine.currentScreen, 'forest');
      expect(responses.map((item) => item['type']), [
        'state_update',
        'bird_count',
      ]);
      expect(responses.last['visible'], VrSimulationEngine.visibleBirdCount);
      expect(responses.last['left'], VrSimulationEngine.visibleBirdCountLeft);
      expect(responses.last['right'], VrSimulationEngine.visibleBirdCountRight);

      responses = engine.processCommand(_command('back_to_menu'));
      expect(engine.currentScreen, 'info');
      expect(responses.single['current_view'], 'info');
    });

    test('does not invent responses for silent Unity actions', () {
      final engine = VrSimulationEngine();

      final responses = engine.processCommand(_command('move_easel_left'));

      expect(responses, isEmpty);
      expect(engine.lastCommand, 'move_easel_left');
      expect(engine.noResponseMessage, contains('nie wysyła'));
    });

    test('returns a valid JPEG fixture for painting save', () {
      final engine = VrSimulationEngine();

      final response = engine.processCommand(_command('save_painting')).single;
      final bytes = base64.decode(response['image_base64'] as String);

      expect(response['type'], 'canvas_image');
      expect(response['format'], 'jpg');
      expect(bytes.take(2), [0xff, 0xd8]);
      expect(bytes.skip(bytes.length - 2), [0xff, 0xd9]);
    });
  });

  test(
    'provider connects, emits initial state, handles commands, and closes',
    () async {
      final connection = FakeVrSimulationConnection();
      String? requestedUrl;
      final provider = VrSimulationProvider(
        channelFactory: (url) {
          requestedUrl = url;
          return connection;
        },
      );

      await provider.enable('ws://localhost/ws?role=vr_simulator');

      expect(requestedUrl, 'ws://localhost/ws?role=vr_simulator');
      expect(provider.enabled, isTrue);
      expect(provider.connected, isTrue);
      expect(json.decode(connection.sent.single)['current_view'], 'info');

      connection.receive(_command('start_painting'));
      await Future<void>.delayed(Duration.zero);

      expect(provider.currentScreen, 'painting');
      expect(provider.lastCommand, 'start_painting');
      expect(json.decode(connection.sent.last)['current_view'], 'painting');

      provider.disable();
      await Future<void>.delayed(Duration.zero);
      expect(provider.enabled, isFalse);
      expect(provider.connected, isFalse);
      expect(connection.closed, isTrue);
      provider.dispose();
    },
  );
}

List<String> _actionsFor(String screen) => VrSimulationEngine
    .screenActions[screen]!
    .map((item) => item['action']!)
    .toList();

Map<String, dynamic> _command(String action) => {
  'type': 'command',
  'action': action,
};

class FakeVrSimulationConnection implements VrSimulationConnection {
  final _incoming = StreamController<dynamic>();
  final List<String> sent = [];
  bool closed = false;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  Future<void> get ready => Future.value();

  @override
  void add(String message) => sent.add(message);

  void receive(Map<String, dynamic> message) {
    _incoming.add(json.encode(message));
  }

  @override
  Future<void> close() async {
    closed = true;
    await _incoming.close();
  }
}
