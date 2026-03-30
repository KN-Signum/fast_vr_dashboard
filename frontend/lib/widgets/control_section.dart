import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../providers/web_socket_provider.dart';

class ControlSection extends StatelessWidget {
  const ControlSection({super.key});

  @override
  Widget build(BuildContext context) {
    final wsProvider = Provider.of<WebSocketProvider>(context);
    final gameProvider = Provider.of<GameProvider>(context);

    if (wsProvider.channel == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(gameProvider),
          const SizedBox(height: 16),

          // 1. EKRAN POWITALNY / INFO
          if (gameProvider.currentScreen == 'info')
            _buildInfoActions(wsProvider),

          // 2. WYBÓR GIER (MENU)
          if (gameProvider.currentScreen == 'menu')
            _buildMenuActions(wsProvider),

          // 3. DYNAMICZNA KONTROLA DLA SCEN (Las, Malowanie)
          if (gameProvider.currentScreen == 'painting' ||
              gameProvider.currentScreen == 'forest')
            _buildDynamicActions(gameProvider, wsProvider),
        ],
      ),
    );
  }

  Widget _buildHeader(GameProvider gameProvider) {
    // Mapowanie kolorów statusu
    Color statusColor;
    String label;

    switch (gameProvider.currentScreen) {
      case 'painting':
        statusColor = Colors.purple;
        label = "MALOWANIE";
        break;
      case 'forest':
        statusColor = Colors.teal;
        label = "LAS";
        break;
      case 'menu':
        statusColor = Colors.orange;
        label = "MENU";
        break;
      default:
        statusColor = Colors.blue;
        label = "INFO";
        break;
    }

    return Row(
      children: [
        Text(
          'KONTROLA',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
            letterSpacing: 1,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoActions(WebSocketProvider ws) {
    return ElevatedButton.icon(
      onPressed: () =>
          ws.sendMessage({"type": "command", "action": "next_to_selection"}),
      icon: const Icon(Icons.play_arrow),
      label: const Text('Zacznij badanie'),
    );
  }

  Widget _buildMenuActions(WebSocketProvider ws) {
    return Column(
      children: [
        _actionButton(
          ws,
          "start_painting",
          "Malowanie",
          Icons.brush,
          Colors.purple,
        ),
        const SizedBox(height: 8),
        _actionButton(
          ws,
          "start_forest",
          "Spacer w lesie",
          Icons.forest,
          Colors.teal,
        ),
      ],
    );
  }

  Widget _buildDynamicActions(GameProvider game, WebSocketProvider ws) {
    return Column(
      children: [
        // Rysujemy przyciski przesłane przez Unity (SceneStateSync)
        ...game.gameActions.map((actionData) {
          final action = actionData['action'] as String;
          final label = actionData['label'] as String;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _actionButton(
              ws,
              action,
              label,
              _getIcon(action),
              _getColor(action),
            ),
          );
        }),
      ],
    );
  }

  // Pomocniczy widget przycisku, żeby kod był czysty
  Widget _actionButton(
    WebSocketProvider ws,
    String action,
    String label,
    IconData icon,
    Color color,
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => ws.sendMessage({"type": "command", "action": action}),
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  IconData _getIcon(String action) {
    if (action.contains('clear')) return Icons.refresh;
    if (action.contains('save')) return Icons.download;
    if (action.contains('next')) return Icons.skip_next;
    if (action.contains('back') || action.contains('exit')) return Icons.logout;
    return Icons.settings;
  }

  Color _getColor(String action) {
    if (action.contains('clear')) return Colors.redAccent;
    if (action.contains('save')) return Colors.blueAccent;
    if (action.contains('back')) return Colors.blueGrey;
    return Colors.indigo;
  }
}
