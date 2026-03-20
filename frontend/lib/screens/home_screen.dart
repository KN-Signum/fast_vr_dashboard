import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/web_socket_provider.dart';
import '../providers/game_provider.dart';
import '../widgets/side_menu.dart';
import '../widgets/viewer.dart';

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
        ],
      ),
    );
  }
}
