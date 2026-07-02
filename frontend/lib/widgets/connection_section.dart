import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/web_socket_provider.dart';

class ConnectionSection extends StatelessWidget {
  const ConnectionSection({super.key});

  String _backendWebSocketUrl() {
    final base = Uri.base;
    if (base.scheme != 'http' && base.scheme != 'https') {
      return 'ws://127.0.0.1:8080/ws';
    }

    final host = base.host.isEmpty ? '127.0.0.1' : base.host;
    final isLocalHost =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final port = isLocalHost && base.hasPort && base.port != 8080
        ? 8080
        : (base.hasPort ? base.port : null);

    return Uri(scheme: scheme, host: host, port: port, path: '/ws').toString();
  }

  @override
  Widget build(BuildContext context) {
    final wsProvider = Provider.of<WebSocketProvider>(context);
    final isConnected = wsProvider.isConnected;
    final wsUrl = _backendWebSocketUrl();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: isConnected
                ? () => wsProvider.disconnect()
                : () => wsProvider.connect(wsUrl),
            icon: Icon(isConnected ? Icons.link_off : Icons.link, size: 18),
            label: Text(isConnected ? 'Rozłącz' : 'Połącz z backendem'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: isConnected
                  ? Colors.red.shade100
                  : Colors.green.shade100,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            wsUrl,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
