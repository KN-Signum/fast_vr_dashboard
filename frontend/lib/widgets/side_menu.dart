import 'package:flutter/material.dart';
import 'connection_section.dart';
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
                  'Created by',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Image.asset("images/signum_light.png", height: 50),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
