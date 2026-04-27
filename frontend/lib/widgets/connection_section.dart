import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/web_socket_provider.dart';

class ConnectionSection extends StatelessWidget {
  const ConnectionSection({super.key});

  @override
  Widget build(BuildContext context) {
    final wsProvider = Provider.of<WebSocketProvider>(context);
    final isConnected = wsProvider.isConnected;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton.icon(
        onPressed: isConnected
            ? () => wsProvider.disconnect()
            : () => wsProvider.connect('ws://127.0.0.1:8080/ws'),
        icon: Icon(isConnected ? Icons.link_off : Icons.link, size: 18),
        label: Text(isConnected ? 'Rozłącz' : 'Połącz'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: isConnected
              ? Colors.red.shade100
              : Colors.green.shade100,
        ),
      ),
    );
  }
}
