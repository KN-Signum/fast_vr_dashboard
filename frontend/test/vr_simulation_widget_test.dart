import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vr_fast_dashboard/providers/eeg_control_provider.dart';
import 'package:vr_fast_dashboard/providers/eeg_provider.dart';
import 'package:vr_fast_dashboard/providers/eye_tracking_provider.dart';
import 'package:vr_fast_dashboard/providers/session_provider.dart';
import 'package:vr_fast_dashboard/providers/session_file_storage_provider.dart';
import 'package:vr_fast_dashboard/providers/vr_simulation_provider.dart';
import 'package:vr_fast_dashboard/providers/web_socket_provider.dart';
import 'package:vr_fast_dashboard/screens/session_setup_screen.dart';
import 'package:vr_fast_dashboard/services/eeg_control_api.dart';
import 'package:vr_fast_dashboard/services/session_api.dart';
import 'package:vr_fast_dashboard/services/session_file_store_factory.dart';
import 'package:vr_fast_dashboard/widgets/vr_simulation_preview.dart';

void main() {
  testWidgets('shows the VR simulation switch on session setup', (
    tester,
  ) async {
    final providers = _TestProviders();
    await tester.binding.setSurfaceSize(const Size(1200, 900));

    await tester.pumpWidget(
      providers.wrap(const MaterialApp(home: SessionSetupScreen())),
    );

    expect(find.byKey(const ValueKey('vr-simulation-switch')), findsOneWidget);
    expect(find.text('Folder zapisu'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    providers.dispose();
  });

  testWidgets('simulation preview shows screen, command, and VR response', (
    tester,
  ) async {
    final connection = _FakeConnection();
    final providers = _TestProviders(connection: connection);
    await providers.simulation.enable('ws://test/ws?role=vr_simulator');
    await tester.binding.setSurfaceSize(const Size(1000, 760));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 900,
              height: 700,
              child: VrSimulationPreview(simulation: providers.simulation),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('vr-simulation-preview')), findsOneWidget);
    expect(find.text('EKRAN INFORMACYJNY'), findsOneWidget);

    connection.receive({'type': 'command', 'action': 'start_forest'});
    await tester.pump();

    expect(find.text('SPACER W LESIE'), findsOneWidget);
    expect(find.text('start_forest'), findsOneWidget);
    expect(find.textContaining('bird_count'), findsOneWidget);

    connection.receive({'type': 'command', 'action': 'pause_walk'});
    await tester.pump();

    expect(find.text('pause_walk'), findsOneWidget);
    expect(find.textContaining('nie wysyła'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    providers.dispose();
  });
}

class _TestProviders {
  _TestProviders({_FakeConnection? connection})
    : simulation = VrSimulationProvider(
        channelFactory: (_) => connection ?? _FakeConnection(),
      ),
      session = SessionProvider(api: _FakeSessionApi()),
      fileStorage = SessionFileStorageProvider(store: createSessionFileStore()),
      eegControl = EegControlProvider(api: _FakeEegControlApi());

  final VrSimulationProvider simulation;
  final SessionProvider session;
  final SessionFileStorageProvider fileStorage;
  final EegControlProvider eegControl;
  final WebSocketProvider websocket = WebSocketProvider();
  final EyeTrackingProvider eyeTracking = EyeTrackingProvider();
  final EegProvider eeg = EegProvider();

  Widget wrap(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: simulation),
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: fileStorage),
        ChangeNotifierProvider.value(value: eegControl),
        ChangeNotifierProvider.value(value: websocket),
        ChangeNotifierProvider.value(value: eyeTracking),
        ChangeNotifierProvider.value(value: eeg),
      ],
      child: child,
    );
  }

  void dispose() {
    simulation.dispose();
    session.dispose();
    fileStorage.dispose();
    eegControl.dispose();
    websocket.dispose();
    eyeTracking.dispose();
    eeg.dispose();
  }
}

class _FakeConnection implements VrSimulationConnection {
  final _incoming = StreamController<dynamic>();

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  Future<void> get ready => Future.value();

  @override
  void add(String message) {}

  void receive(Map<String, dynamic> message) {
    _incoming.add(json.encode(message));
  }

  @override
  Future<void> close() => _incoming.close();
}

class _FakeEegControlApi implements EegControlApi {
  @override
  Future<Map<String, dynamic>> state() async => {
    'eeg_enabled': false,
    'eeg_mode': 'off',
    'eeg_status': 'disabled',
  };

  @override
  Future<Map<String, dynamic>> setEnabled(bool enabled) async => state();

  @override
  void close() {}
}

class _FakeSessionApi implements SessionApi {
  @override
  Future<Map<String, dynamic>?> activeSession() async => null;

  @override
  Future<Map<String, dynamic>?> recoveredSession() async => null;

  @override
  Future<Map<String, dynamic>> createSession({
    required String patientId,
    required String preferredHand,
    required String notes,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> addEvent({
    required String sessionId,
    required String label,
    required String category,
    required String note,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> endSession(String sessionId) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> updatePostSessionNotes({
    required String sessionId,
    required String notes,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> uploadRawData(String sessionId) =>
      throw UnimplementedError();

  @override
  Uri rawDownloadUri(String sessionId) => Uri();

  @override
  Uri summaryDownloadUri(String sessionId) => Uri();

  @override
  void close() {}
}
