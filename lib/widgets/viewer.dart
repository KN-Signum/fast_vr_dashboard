import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/web_socket_provider.dart';
import '../providers/device_provider.dart';

class Viewer extends StatelessWidget {
  final bool isDrawerOpen;
  final VoidCallback onToggleDrawer;

  const Viewer({
    super.key,
    required this.isDrawerOpen,
    required this.onToggleDrawer,
  });

  @override
  Widget build(BuildContext context) {
    final wsProvider = Provider.of<WebSocketProvider>(context);
    final deviceProvider = Provider.of<DeviceProvider>(context);

    return Expanded(
      child: Stack(
        children: [
          Container(
            color: const Color.fromARGB(255, 255, 255, 255),
            child: Center(
              child: wsProvider.lastFrame == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.videocam_off,
                          size: 64,
                          color: Color.fromARGB(137, 144, 143, 143),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Czekam na pierwszą klatkę…',
                          style: TextStyle(
                            color: Color.fromARGB(137, 144, 143, 143),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    )
                  : InteractiveViewer(
                      child: Image.memory(
                        wsProvider.lastFrame!,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.low,
                        fit: BoxFit.contain,
                      ),
                    ),
            ),
          ),
          if (!isDrawerOpen)
            Positioned(
              top: 16,
              left: 16,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: onToggleDrawer,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isDrawerOpen ? Icons.menu_open : Icons.menu,
                          size: 20,
                          color: Colors.grey.shade700,
                        ),
                        if (!isDrawerOpen &&
                            deviceProvider.selectedDevice != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            wsProvider.channel != null
                                ? Icons.cast_connected
                                : Icons.cast,
                            size: 18,
                            color: wsProvider.channel != null
                                ? Colors.green
                                : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            deviceProvider.selectedDevice!.host,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
