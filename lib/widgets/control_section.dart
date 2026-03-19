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

    if (wsProvider.channel == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                  color: gameProvider.currentScreen == 'info'
                      ? Colors.blue.shade100
                      : gameProvider.currentScreen == 'menu'
                      ? Colors.orange.shade100
                      : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  gameProvider.currentScreen == 'info'
                      ? 'INFO'
                      : gameProvider.currentScreen == 'menu'
                      ? 'MENU'
                      : 'GRA',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: gameProvider.currentScreen == 'info'
                        ? Colors.blue.shade700
                        : gameProvider.currentScreen == 'menu'
                        ? Colors.orange.shade700
                        : Colors.green.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Buttons for INFO screen
          if (gameProvider.currentScreen == 'info') ...[
            ElevatedButton.icon(
              onPressed: () {
                gameProvider.setCurrentScreen('menu');
                wsProvider.sendMessage({'action': 'next'});
              },
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Dalej'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],

          // Buttons for MENU screen
          if (gameProvider.currentScreen == 'menu') ...[
            ElevatedButton.icon(
              onPressed: () =>
                  wsProvider.sendMessage({'action': 'start_game_draw'}),
              icon: const Icon(Icons.brush, size: 18),
              label: const Text('Gra Rysunkowa'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () =>
                  wsProvider.sendMessage({'action': 'start_game_forest_walk'}),
              icon: const Icon(Icons.nature, size: 18),
              label: const Text('Spacer po Lesie'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
          ],

          // Buttons for GAME screen
          if (gameProvider.currentScreen == 'game') ...[
            ...gameProvider.gameActions.map((action) {
              final actionId = action['id'] as String;
              final actionName = action['name'] as String;

              IconData icon;
              Color color;

              if (actionId == 'save_canvas') {
                icon = Icons.save;
                color = Colors.blue;
              } else if (actionId == 'clear_canvas') {
                icon = Icons.clear;
                color = Colors.red;
              } else {
                icon = Icons.touch_app;
                color = Colors.grey;
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ElevatedButton.icon(
                  onPressed: () => wsProvider.sendMessage({'action': actionId}),
                  icon: Icon(icon, size: 18),
                  label: Text(actionName),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                  ),
                ),
              );
            }).toList(),
            ElevatedButton.icon(
              onPressed: () => wsProvider.sendMessage({'action': 'exit_game'}),
              icon: const Icon(Icons.exit_to_app, size: 18),
              label: const Text('Wyjdź do Menu'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
