import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/eeg_provider.dart';
import '../providers/eye_tracking_provider.dart';
import '../providers/session_provider.dart';
import '../providers/web_socket_provider.dart';
import '../providers/vr_simulation_provider.dart';
import '../theme/app_style.dart';
import 'control_section.dart';
import 'post_session_notes_dialog.dart';

class SideMenu extends StatelessWidget {
  final bool isOpen;
  final VoidCallback onToggle;

  const SideMenu({super.key, required this.isOpen, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    if (!isOpen) {
      return const SizedBox.shrink();
    }
    final session = context.watch<SessionProvider>();

    return Container(
      width: 200,
      decoration: const BoxDecoration(color: AppColors.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SessionHeader(onToggle: onToggle),
          const _LiveStatusStrip(),
          const Divider(height: 1),
          const Expanded(child: SingleChildScrollView(child: ControlSection())),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: session.isBusy
                  ? null
                  : () async {
                      await showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) =>
                            PostSessionNotesDialog(session: session),
                      );
                    },
              icon: const Icon(Icons.stop_circle),
              label: const Text('Zakończ sesję'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade100,
                foregroundColor: Colors.red.shade900,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Autor',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Image.asset(
                  'assets/images/signum_light.png',
                  height: 52,
                  width: double.infinity,
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.contain,
                  semanticLabel: 'Logo KN Signum',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionHeader extends StatelessWidget {
  final VoidCallback onToggle;

  const _SessionHeader({required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(color: AppColors.primaryDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Panel NEXT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
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
          const SizedBox(height: 14),
          Text(
            session.patientId,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            session.sessionId ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFCFE2F7), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _LiveStatusStrip extends StatefulWidget {
  const _LiveStatusStrip();

  @override
  State<_LiveStatusStrip> createState() => _LiveStatusStripState();
}

class _LiveStatusStripState extends State<_LiveStatusStrip> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketProvider>();
    final eeg = context.watch<EegProvider>();
    final eyeTracking = context.watch<EyeTrackingProvider>();
    final vrSimulation = context.watch<VrSimulationProvider>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: _CompactStatus(
              label: 'Serwer',
              online: ws.isConnected,
              icon: Icons.hub,
            ),
          ),
          Expanded(
            child: _CompactStatus(
              label: 'EEG',
              online: _isRecent(eeg.latest?.timestamp),
              icon: Icons.psychology,
            ),
          ),
          Expanded(
            child: _CompactStatus(
              label: vrSimulation.enabled ? 'VR · SYMULACJA' : 'VR',
              online: vrSimulation.connected || _isRecent(ws.lastFrameAt),
              icon: Icons.videocam,
            ),
          ),
          Expanded(
            child: _CompactStatus(
              label: 'Wzrok',
              online: eyeTracking.isReceiving,
              icon: Icons.visibility,
            ),
          ),
        ],
      ),
    );
  }

  bool _isRecent(DateTime? value) {
    if (value == null) return false;
    return DateTime.now().difference(value) <= const Duration(seconds: 3);
  }
}

class _CompactStatus extends StatelessWidget {
  final String label;
  final bool online;
  final IconData icon;

  const _CompactStatus({
    required this.label,
    required this.online,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final color = online ? AppColors.success : AppColors.warning;
    final status = online ? 'połączono' : 'oczekuje';
    return Tooltip(
      message: '$label: $status',
      child: Semantics(
        label: '$label: $status',
        child: SizedBox(
          height: 28,
          child: Center(child: Icon(icon, size: 20, color: color)),
        ),
      ),
    );
  }
}
