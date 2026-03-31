import 'package:flutter/material.dart';
import 'connection_section.dart';
import 'device_list.dart';
import 'control_section.dart';

class SideMenu extends StatelessWidget {
  final bool isOpen;
  final VoidCallback onToggle;

  const SideMenu({super.key, required this.isOpen, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    if (!isOpen) {
      return const SizedBox.shrink();
    }

    return Container(
      width: 260,
      decoration: BoxDecoration(color: Colors.grey.shade100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.blue.shade700),
            child: Row(
              children: [
                Text(
                  'NEXT Dashboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onToggle,
                  icon: const Icon(Icons.chevron_left),
                  color: Colors.white,
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const ConnectionSection(),
          const DeviceList(),
          const ControlSection(),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wymagania Systemowe:',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '• Unity: Client Mode (Active)\n'
                  '• Python: FastAPI (Port 8080)\n'
                  '• Protocol: JSON + Binary (Wasm)',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.grey.shade600,
                    height: 1.4,
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
