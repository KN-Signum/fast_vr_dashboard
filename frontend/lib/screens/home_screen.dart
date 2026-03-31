import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/web_socket_provider.dart';
import '../providers/game_provider.dart';
import '../providers/eye_tracking_provider.dart';
import '../providers/eeg_provider.dart';
import '../widgets/side_menu.dart';
import '../widgets/viewer.dart';
import '../widgets/eeg_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _drawerOpen = true;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    // Listen to WebSocket messages to update the GameProvider
    final wsProvider = Provider.of<WebSocketProvider>(context, listen: false);
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final eyeTrackingProvider = Provider.of<EyeTrackingProvider>(
      context,
      listen: false,
    );

    // Wire up eye tracking callback from WebSocket
    wsProvider.setEyeTrackingCallback((data) {
      eyeTrackingProvider.updateFromJson(data);
    });

    // Wire up EEG callback from WebSocket
    final eegProvider = Provider.of<EegProvider>(context, listen: false);
    wsProvider.setEegCallback((data) {
      eegProvider.updateFromJson(data);
    });

    _subscription = wsProvider.stream.listen((message) {
      if (message is String) {
        gameProvider.handleMessage(message, wsProvider.lastFrame);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SideMenu(
            isOpen: _drawerOpen,
            onToggle: () {
              setState(() => _drawerOpen = !_drawerOpen);
            },
          ),
          Viewer(
            isDrawerOpen: _drawerOpen,
            onToggleDrawer: () {
              setState(() => _drawerOpen = !_drawerOpen);
            },
          ),
          const EegPanel(),
        ],
      ),
    );
  }
}
