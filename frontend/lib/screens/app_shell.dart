import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/eeg_provider.dart';
import '../providers/eye_tracking_provider.dart';
import '../providers/game_provider.dart';
import '../providers/session_provider.dart';
import '../providers/web_socket_provider.dart';
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

  @override
  void initState() {
    super.initState();

    final wsProvider = context.read<WebSocketProvider>();
    final gameProvider = context.read<GameProvider>();
    final eyeTrackingProvider = context.read<EyeTrackingProvider>();
    final eegProvider = context.read<EegProvider>();
    final sessionProvider = context.read<SessionProvider>();

    wsProvider.setEyeTrackingCallback((data) {
      eyeTrackingProvider.updateFromJson(data);
      sessionProvider.recordEyeTracking(data);
    });

    wsProvider.setEegCallback((data) {
      eegProvider.updateFromJson(data);
      sessionProvider.recordEeg(data);
    });

    _subscription = wsProvider.stream.listen((message) {
      if (message is String) {
        gameProvider.handleMessage(message);
        sessionProvider.recordVrJsonMessage(message);
      } else if (message is Uint8List) {
        sessionProvider.recordVrFrame(message.lengthInBytes);
      }
    });

    wsProvider.connect(WebSocketProvider.defaultBackendUrl());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = context.watch<SessionProvider>().stage;

    return switch (stage) {
      SessionStage.setup => const SessionSetupScreen(),
      SessionStage.active => const HomeScreen(),
      SessionStage.summary => const SessionSummaryScreen(),
    };
  }
}
