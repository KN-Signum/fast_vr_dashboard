import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/eeg_provider.dart';
import '../providers/eye_tracking_provider.dart';
import '../providers/session_provider.dart';
import '../providers/web_socket_provider.dart';
import '../theme/app_style.dart';
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
                      final success = await session.endSession();
                      if (!success &&
                          context.mounted &&
                          session.errorMessage != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(session.errorMessage!)),
                        );
                      }
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
            padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 12),
          const _ElapsedTimer(),
        ],
      ),
    );
  }
}

class _ElapsedTimer extends StatefulWidget {
  const _ElapsedTimer();

  @override
  State<_ElapsedTimer> createState() => _ElapsedTimerState();
}

class _ElapsedTimerState extends State<_ElapsedTimer> {
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
    final duration = context.watch<SessionProvider>().duration;
    return Row(
      children: [
        const Icon(Icons.timer, size: 15, color: Color(0xFFCFE2F7)),
        const SizedBox(width: 6),
        Text(
          _formatDuration(duration),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration? value) {
    if (value == null) return '0:00:00';
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
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

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'DANE NA ŻYWO',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          _CompactStatus(
            label: 'Serwer',
            online: ws.isConnected,
            icon: Icons.hub,
          ),
          _CompactStatus(
            label: 'EEG',
            online: _isRecent(eeg.latest?.timestamp),
            icon: Icons.psychology,
          ),
          _CompactStatus(
            label: 'VR',
            online: _isRecent(ws.lastFrameAt),
            icon: Icons.videocam,
          ),
          _CompactStatus(
            label: 'Wzrok',
            online: eyeTracking.isReceiving,
            icon: Icons.visibility,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}
