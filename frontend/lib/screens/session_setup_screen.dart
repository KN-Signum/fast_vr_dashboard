import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/eeg_provider.dart';
import '../providers/session_provider.dart';
import '../providers/web_socket_provider.dart';
import '../theme/app_style.dart';

class SessionSetupScreen extends StatefulWidget {
  const SessionSetupScreen({super.key});

  @override
  State<SessionSetupScreen> createState() => _SessionSetupScreenState();
}

class _SessionSetupScreenState extends State<SessionSetupScreen> {
  final _patientIdController = TextEditingController();
  final _notesController = TextEditingController();
  String _preferredHand = 'not_specified';
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _patientIdController.addListener(_onFormChanged);
    _statusTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _patientIdController
      ..removeListener(_onFormChanged)
      ..dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onFormChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketProvider>();
    final eeg = context.watch<EegProvider>();
    final session = context.read<SessionProvider>();
    final patientId = _patientIdController.text.trim();

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppHeader(
                  title: 'NEXT Dashboard',
                  subtitle: 'Create a session and verify device readiness.',
                  trailing: StatusPill(
                    label: ws.isConnected
                        ? 'BACKEND ONLINE'
                        : 'BACKEND WAITING',
                    online: ws.isConnected,
                    icon: Icons.hub,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _SessionFormCard(
                        patientIdController: _patientIdController,
                        notesController: _notesController,
                        preferredHand: _preferredHand,
                        onPreferredHandChanged: (value) {
                          if (value == null) return;
                          setState(() => _preferredHand = value);
                        },
                        onCreate: patientId.isEmpty
                            ? null
                            : () {
                                session.createSession(
                                  patientId: patientId,
                                  preferredHand: _preferredHand,
                                  notes: _notesController.text,
                                );
                              },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      flex: 2,
                      child: _ConnectionStatusCard(
                        backendOnline: ws.isConnected,
                        eegOnline: _isRecent(eeg.latest?.timestamp),
                        vrOnline: _isRecent(_latestVrAt(ws)),
                        backendDetail: ws.status,
                        eegDetail: eeg.latest == null
                            ? 'Waiting for EEG data'
                            : 'Last EEG ${_formatAge(eeg.latest!.timestamp)} ago',
                        vrDetail: _latestVrAt(ws) == null
                            ? 'Waiting for VR data'
                            : 'Last VR ${_formatAge(_latestVrAt(ws)!)} ago',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DateTime? _latestVrAt(WebSocketProvider ws) {
    final frameAt = ws.lastFrameAt;
    final messageAt = ws.lastVrMessageAt;
    if (frameAt == null) return messageAt;
    if (messageAt == null) return frameAt;
    return frameAt.isAfter(messageAt) ? frameAt : messageAt;
  }

  bool _isRecent(DateTime? value) {
    if (value == null) return false;
    return DateTime.now().difference(value) <= const Duration(seconds: 3);
  }

  String _formatAge(DateTime value) {
    final seconds = DateTime.now().difference(value).inSeconds;
    return '${seconds}s';
  }
}

class _SessionFormCard extends StatelessWidget {
  final TextEditingController patientIdController;
  final TextEditingController notesController;
  final String preferredHand;
  final ValueChanged<String?> onPreferredHandChanged;
  final VoidCallback? onCreate;

  const _SessionFormCard({
    required this.patientIdController,
    required this.notesController,
    required this.preferredHand,
    required this.onPreferredHandChanged,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return SectionPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.assignment, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'New session',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: patientIdController,
            decoration: appInputDecoration('Patient ID'),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: preferredHand,
            decoration: appInputDecoration('Preferred hand'),
            items: const [
              DropdownMenuItem(
                value: 'not_specified',
                child: Text('Not specified'),
              ),
              DropdownMenuItem(value: 'left', child: Text('Left')),
              DropdownMenuItem(value: 'right', child: Text('Right')),
              DropdownMenuItem(
                value: 'ambidextrous',
                child: Text('Ambidextrous'),
              ),
            ],
            onChanged: onPreferredHandChanged,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: notesController,
            minLines: 3,
            maxLines: 5,
            decoration: appInputDecoration(
              'Notes',
            ).copyWith(alignLabelWithHint: true),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Create session'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionStatusCard extends StatelessWidget {
  final bool backendOnline;
  final bool eegOnline;
  final bool vrOnline;
  final String backendDetail;
  final String eegDetail;
  final String vrDetail;

  const _ConnectionStatusCard({
    required this.backendOnline,
    required this.eegOnline,
    required this.vrOnline,
    required this.backendDetail,
    required this.eegDetail,
    required this.vrDetail,
  });

  @override
  Widget build(BuildContext context) {
    return SectionPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Device readiness',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _StatusRow(
            icon: Icons.hub,
            label: 'Backend',
            online: backendOnline,
            detail: backendDetail,
          ),
          _StatusRow(
            icon: Icons.psychology,
            label: 'EEG',
            online: eegOnline,
            detail: eegDetail,
          ),
          _StatusRow(
            icon: Icons.videocam,
            label: 'VR',
            online: vrOnline,
            detail: vrDetail,
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool online;
  final String detail;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.online,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final color = online ? AppColors.success : AppColors.warning;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            StatusPill(label: online ? 'ONLINE' : 'WAITING', online: online),
          ],
        ),
      ),
    );
  }
}
