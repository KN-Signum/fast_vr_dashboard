import 'package:flutter/material.dart';
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
