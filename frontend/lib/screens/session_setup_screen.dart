import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/eeg_provider.dart';
import '../providers/eeg_control_provider.dart';
import '../providers/eye_tracking_provider.dart';
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
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {});
      if (timer.tick.isEven) {
        unawaited(context.read<EegControlProvider>().refresh());
      }
    });
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
    final eegControl = context.watch<EegControlProvider>();
    final eyeTracking = context.watch<EyeTrackingProvider>();
    final session = context.watch<SessionProvider>();
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
                  title: 'Panel NEXT',
                  subtitle: 'Utwórz sesję i sprawdź gotowość urządzeń.',
                  trailing: StatusPill(
                    label: ws.isConnected
                        ? 'SERWER POŁĄCZONY'
                        : 'OCZEKIWANIE NA SERWER',
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
                        errorMessage: session.errorMessage,
                        onPreferredHandChanged: (value) {
                          if (value == null) return;
                          setState(() => _preferredHand = value);
                        },
                        onCreate: patientId.isEmpty || session.isBusy
                            ? null
                            : () async {
                                await session.createSession(
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
                        eegOnline:
                            eegControl.enabled &&
                            _isRecent(eeg.latest?.timestamp),
                        eegEnabled: eegControl.enabled,
                        eegToggleEnabled:
                            eegControl.hasLoaded &&
                            eegControl.isAvailable &&
                            !eegControl.isBusy,
                        eegToggleBusy: eegControl.isBusy,
                        vrOnline: _isRecent(ws.lastFrameAt),
                        eyeTrackingOnline: eyeTracking.isReceiving,
                        backendDetail: ws.status,
                        eegDetail: _eegDetail(eegControl, eeg),
                        onEegEnabledChanged: (enabled) {
                          unawaited(eegControl.setEnabled(enabled));
                        },
                        vrDetail: ws.lastFrameAt == null
                            ? 'Oczekiwanie na podgląd wideo'
                            : 'Ostatnia klatka ${_formatAge(ws.lastFrameAt!)} temu',
                        eyeTrackingDetail: ws.lastEyeTrackingAt == null
                            ? 'Oczekiwanie na dane z gogli'
                            : 'Ostatni punkt wzroku ${_formatAge(ws.lastEyeTrackingAt!)} temu',
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

  bool _isRecent(DateTime? value) {
    if (value == null) return false;
    return DateTime.now().difference(value) <= const Duration(seconds: 3);
  }

  String _formatAge(DateTime value) {
    final seconds = DateTime.now().difference(value).inSeconds;
    return '$seconds s';
  }

  String _eegDetail(EegControlProvider control, EegProvider eeg) {
    if (!control.hasLoaded) return 'Sprawdzanie ustawienia EEG';
    if (!control.isAvailable) return 'Wyłączone w konfiguracji serwera';
    if (!control.enabled) return 'Wyłączone przez operatora';
    if (control.isBusy) return 'Zmiana ustawienia EEG';
    if (control.requestError != null) return control.requestError!;
    if (control.status == 'error') {
      return control.eegError ?? 'Błąd połączenia z EEG';
    }
    if (control.status == 'connecting') {
      return control.deviceName.isEmpty
          ? 'Wyszukiwanie urządzenia EEG'
          : 'Łączenie z ${control.deviceName}';
    }
    if (eeg.latest == null) return 'Oczekiwanie na dane EEG';
    return 'Ostatnie EEG ${_formatAge(eeg.latest!.timestamp)} temu';
  }
}

class _SessionFormCard extends StatelessWidget {
  final TextEditingController patientIdController;
  final TextEditingController notesController;
  final String preferredHand;
  final String? errorMessage;
  final ValueChanged<String?> onPreferredHandChanged;
  final VoidCallback? onCreate;

  const _SessionFormCard({
    required this.patientIdController,
    required this.notesController,
    required this.preferredHand,
    required this.errorMessage,
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
                  'Nowa sesja',
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
            decoration: appInputDecoration('ID pacjenta'),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: preferredHand,
            decoration: appInputDecoration('Preferowana ręka'),
            items: const [
              DropdownMenuItem(
                value: 'not_specified',
                child: Text('Nie określono'),
              ),
              DropdownMenuItem(value: 'left', child: Text('Lewa')),
              DropdownMenuItem(value: 'right', child: Text('Prawa')),
              DropdownMenuItem(value: 'ambidextrous', child: Text('Oburęczny')),
            ],
            onChanged: onPreferredHandChanged,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: notesController,
            minLines: 3,
            maxLines: 5,
            decoration: appInputDecoration(
              'Notatki przed sesją',
            ).copyWith(alignLabelWithHint: true),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Utwórz sesję'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              errorMessage!,
              style: const TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConnectionStatusCard extends StatelessWidget {
  final bool backendOnline;
  final bool eegOnline;
  final bool eegEnabled;
  final bool eegToggleEnabled;
  final bool eegToggleBusy;
  final bool vrOnline;
  final bool eyeTrackingOnline;
  final String backendDetail;
  final String eegDetail;
  final String vrDetail;
  final String eyeTrackingDetail;
  final ValueChanged<bool> onEegEnabledChanged;

  const _ConnectionStatusCard({
    required this.backendOnline,
    required this.eegOnline,
    required this.eegEnabled,
    required this.eegToggleEnabled,
    required this.eegToggleBusy,
    required this.vrOnline,
    required this.eyeTrackingOnline,
    required this.backendDetail,
    required this.eegDetail,
    required this.vrDetail,
    required this.eyeTrackingDetail,
    required this.onEegEnabledChanged,
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
                'Gotowość urządzeń',
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
            label: 'Serwer',
            online: backendOnline,
            detail: backendDetail,
          ),
          _StatusRow(
            icon: Icons.psychology,
            label: 'EEG',
            online: eegOnline,
            detail: eegDetail,
            disabled: !eegEnabled,
            trailing: Tooltip(
              message: eegEnabled ? 'Wyłącz EEG' : 'Włącz EEG',
              child: eegToggleBusy
                  ? const SizedBox(
                      width: 40,
                      height: 40,
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Switch(
                      key: const Key('eeg-enabled-switch'),
                      value: eegEnabled,
                      onChanged: eegToggleEnabled ? onEegEnabledChanged : null,
                    ),
            ),
          ),
          _StatusRow(
            icon: Icons.videocam,
            label: 'VR',
            online: vrOnline,
            detail: vrDetail,
          ),
          _StatusRow(
            icon: Icons.visibility,
            label: 'Wzrok',
            online: eyeTrackingOnline,
            detail: eyeTrackingDetail,
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
  final bool disabled;
  final Widget? trailing;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.online,
    required this.detail,
    this.disabled = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final color = disabled
        ? AppColors.muted
        : online
        ? AppColors.success
        : AppColors.warning;

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
            trailing ??
                StatusPill(
                  label: online ? 'POŁĄCZONO' : 'OCZEKUJE',
                  online: online,
                ),
          ],
        ),
      ),
    );
  }
}
