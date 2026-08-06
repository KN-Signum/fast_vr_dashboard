import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/eeg_provider.dart';
import '../providers/eeg_control_provider.dart';
import '../providers/eye_tracking_provider.dart';
import '../providers/game_provider.dart';
import '../providers/session_provider.dart';
import '../providers/web_socket_provider.dart';
import '../providers/vr_simulation_provider.dart';
import 'home_screen.dart';
import 'session_setup_screen.dart';
import 'session_summary_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  StreamSubscription? _subscription;
  SessionProvider? _sessionProvider;
  SessionStage _lastSessionStage = SessionStage.loading;

  @override
  void initState() {
    super.initState();

    final wsProvider = context.read<WebSocketProvider>();
    final gameProvider = context.read<GameProvider>();
    final eyeTrackingProvider = context.read<EyeTrackingProvider>();
    final eegProvider = context.read<EegProvider>();
    final eegControlProvider = context.read<EegControlProvider>();
    final sessionProvider = context.read<SessionProvider>();
    _sessionProvider = sessionProvider;
    _lastSessionStage = sessionProvider.stage;
    sessionProvider.addListener(_handleSessionStageChanged);

    wsProvider.setEyeTrackingCallback((data) {
      eyeTrackingProvider.updateFromJson(data);
    });

    wsProvider.setEegCallback((data) {
      eegProvider.updateFromJson(data);
    });

    _subscription = wsProvider.stream.listen((message) {
      if (message is String) {
        gameProvider.handleMessage(
          message,
          patientId: sessionProvider.patientId,
        );
      }
    });

    unawaited(sessionProvider.restoreActiveSession());
    unawaited(eegControlProvider.refresh());
    wsProvider.connect(WebSocketProvider.defaultBackendUrl());
  }

  @override
  void dispose() {
    _sessionProvider?.removeListener(_handleSessionStageChanged);
    _subscription?.cancel();
    super.dispose();
  }

  void _handleSessionStageChanged() {
    final session = _sessionProvider;
    if (session == null || session.stage == _lastSessionStage) return;

    final previousStage = _lastSessionStage;
    _lastSessionStage = session.stage;

    if (session.stage == SessionStage.active) {
      context.read<WebSocketProvider>().sendMessage({
        'type': 'command',
        'action': 'request_state',
      });
    } else if (previousStage == SessionStage.active) {
      context.read<VrSimulationProvider>().disable();
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = context.watch<SessionProvider>().stage;

    return switch (stage) {
      SessionStage.loading => const _SessionLoadingScreen(),
      SessionStage.setup => const SessionSetupScreen(),
      SessionStage.active => const HomeScreen(),
      SessionStage.summary => const SessionSummaryScreen(),
    };
  }
}

class _SessionLoadingScreen extends StatelessWidget {
  const _SessionLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
