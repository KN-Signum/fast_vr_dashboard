import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';
import '../providers/web_socket_provider.dart';

class ConnectionSection extends StatefulWidget {
  const ConnectionSection({super.key});

  @override
  State<ConnectionSection> createState() => _ConnectionSectionState();
}

class _ConnectionSectionState extends State<ConnectionSection> {
  final _manualIpController = TextEditingController();

  @override
  void dispose() {
    _manualIpController.dispose();
    super.dispose();
  }

  void _connectManual() {
    var ip = _manualIpController.text.trim();
    if (ip.isEmpty) {
      ip = '127.0.0.1';
    }

    if (ip.startsWith('http://')) ip = ip.substring(7);
    if (ip.startsWith('https://')) ip = ip.substring(8);
    if (ip.startsWith('ws://')) ip = ip.substring(5);
    if (ip.startsWith('wss://')) ip = ip.substring(6);
    if (ip.endsWith('/')) ip = ip.substring(0, ip.length - 1);

    final deviceProvider = Provider.of<DeviceProvider>(context, listen: false);
    deviceProvider.addManualDevice(ip);
    final wsProvider = Provider.of<WebSocketProvider>(context, listen: false);
    wsProvider.connect('ws://$ip:8080/ws');
  }

  @override
  Widget build(BuildContext context) {
    final deviceProvider = Provider.of<DeviceProvider>(context);
    final wsProvider = Provider.of<WebSocketProvider>(context);

    if (wsProvider.channel != null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'POŁĄCZENIE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: deviceProvider.isScanning
                ? null
                : () => deviceProvider.startScanning(),
            icon: deviceProvider.isScanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.search, size: 18),
            label: Text(
              deviceProvider.isScanning ? 'Szukam...' : 'Szukaj gogli',
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'LUB WPROWADŹ IP',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualIpController,
                  decoration: InputDecoration(
                    hintText: '192.168.1.100',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.blue.shade300,
                        width: 2,
                      ),
                    ),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _connectManual,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                child: const Icon(Icons.link, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Icon(
                  deviceProvider.isScanning
                      ? Icons.hourglass_empty
                      : deviceProvider.devices.isNotEmpty
                      ? Icons.check_circle
                      : Icons.info_outline,
                  size: 18,
                  color: deviceProvider.isScanning
                      ? Colors.orange
                      : deviceProvider.devices.isNotEmpty
                      ? Colors.green
                      : Colors.grey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    deviceProvider.status,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
