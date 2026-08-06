import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;

import '../providers/session_provider.dart';
import '../providers/session_file_storage_provider.dart';
import '../theme/app_style.dart' hide MetricTile;
import '../utils/download_filename.dart';
import '../widgets/eye_tracking_summary_card.dart';

class SessionSummaryScreen extends StatelessWidget {
  const SessionSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final fileStorage = context.watch<SessionFileStorageProvider>();
    final report = session.summaryReport();
    final counts = report['counts'] as Map<String, dynamic>;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SummaryHeader(session: session, fileStorage: fileStorage),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _MetadataCard(session: session)),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: _CountsCard(
                          counts: counts,
                          droppedRecords:
                              report['dropped_records'] as int? ?? 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  EyeTrackingSummaryCard(
                    analysis: report['eye_tracking_analysis'] is Map
                        ? Map<String, dynamic>.from(
                            report['eye_tracking_analysis'] as Map,
                          )
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _DownloadCard(session: session, fileStorage: fileStorage),
                  if (session.sessionEvents.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _EventsCard(events: session.sessionEvents),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  final SessionProvider session;
  final SessionFileStorageProvider fileStorage;

  const _SummaryHeader({required this.session, required this.fileStorage});

  @override
  Widget build(BuildContext context) {
    return AppHeader(
      title: session.status == 'interrupted'
          ? 'Odzyskana przerwana sesja'
          : 'Podsumowanie sesji',
      subtitle: session.sessionId ?? 'Brak sesji',
      trailing: OutlinedButton.icon(
        onPressed: () {
          fileStorage.clear();
          session.startNewSession();
        },
        icon: const Icon(Icons.add),
        label: const Text('Nowa sesja'),
      ),
    );
  }
}

class _MetadataCard extends StatelessWidget {
  final SessionProvider session;

  const _MetadataCard({required this.session});

  @override
  Widget build(BuildContext context) {
    return _SummaryCard(
      title: 'Pacjent',
      icon: Icons.badge,
      children: [
        _InfoRow(label: 'ID pacjenta', value: session.patientId),
        _InfoRow(
          label: 'Preferowana ręka',
          value: _formatHand(session.preferredHand),
        ),
        _InfoRow(label: 'Rozpoczęcie', value: _formatDate(session.startedAt)),
        _InfoRow(label: 'Zakończenie', value: _formatDate(session.endedAt)),
        _InfoRow(
          label: 'Czas trwania',
          value: _formatDuration(session.duration),
        ),
        if (session.notes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Notatki przed sesją',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(session.notes),
        ],
        if (session.postSessionNotes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Notatki po sesji',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(session.postSessionNotes),
        ],
      ],
    );
  }

  String _formatHand(String value) {
    return switch (value) {
      'left' => 'Lewa',
      'right' => 'Prawa',
      'ambidextrous' => 'Oburęczny',
      _ => 'Nie określono',
    };
  }
}

class _CountsCard extends StatelessWidget {
  final Map<String, dynamic> counts;
  final int droppedRecords;

  const _CountsCard({required this.counts, required this.droppedRecords});

  @override
  Widget build(BuildContext context) {
    return _SummaryCard(
      title: 'Zarejestrowane dane',
      icon: Icons.dataset,
      children: [
        _MetricTile(
          label: 'Zapisy EEG',
          value: counts['eeg_records'] as int? ?? 0,
          color: AppColors.primary,
        ),
        _MetricTile(
          label: 'Zapisy śledzenia wzroku',
          value: counts['eye_tracking_records'] as int? ?? 0,
          color: AppColors.danger,
        ),
        _MetricTile(
          label: 'Zdarzenia VR',
          value: counts['vr_events'] as int? ?? 0,
          color: AppColors.success,
        ),
        _MetricTile(
          label: 'Klatki VR',
          value: counts['vr_frames'] as int? ?? 0,
          color: const Color(0xFF7656B7),
        ),
        _MetricTile(
          label: 'Zdarzenia obserwowane',
          value: counts['session_events'] as int? ?? 0,
          color: AppColors.warning,
        ),
        if (droppedRecords > 0)
          _MetricTile(
            label: 'Utracone rekordy',
            value: droppedRecords,
            color: AppColors.danger,
          ),
      ],
    );
  }
}

class _DownloadCard extends StatelessWidget {
  final SessionProvider session;
  final SessionFileStorageProvider fileStorage;

  const _DownloadCard({required this.session, required this.fileStorage});

  @override
  Widget build(BuildContext context) {
    final sessionId = session.sessionId ?? 'session';
    final patientId = session.patientId;
    final summaryUri = session.summaryDownloadUri;
    final rawUri = session.rawDownloadUri;
    final reportFilename = sessionReportFilename(patientId, sessionId);
    final rawDataFilename = sessionRawDataFilename(patientId, sessionId);
    final usesFolder = fileStorage.isSupported;
    final directoryReady = fileStorage.hasPatientDirectory;

    return _SummaryCard(
      title: 'Pliki sesji',
      icon: Icons.folder_copy,
      children: [
        if (usesFolder) ...[
          Row(
            children: [
              Icon(
                directoryReady ? Icons.folder : Icons.folder_off_outlined,
                size: 18,
                color: directoryReady ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  directoryReady
                      ? '${fileStorage.baseDirectoryName}/${fileStorage.patientDirectoryName}'
                      : 'Folder zapisu wymaga ponownego wybrania',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (!directoryReady)
                OutlinedButton.icon(
                  onPressed: fileStorage.isBusy
                      ? null
                      : () => _selectDirectory(patientId),
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('Wybierz folder'),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed:
                    summaryUri == null ||
                        fileStorage.isBusy ||
                        (usesFolder && !directoryReady)
                    ? null
                    : () => _save(summaryUri, reportFilename),
                icon: Icon(
                  fileStorage.savedFiles.contains(reportFilename)
                      ? Icons.check
                      : Icons.picture_as_pdf,
                ),
                label: Text(usesFolder ? 'Zapisz raport' : 'Pobierz raport'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed:
                    rawUri == null ||
                        fileStorage.isBusy ||
                        (usesFolder && !directoryReady)
                    ? null
                    : () => _save(rawUri, rawDataFilename),
                icon: Icon(
                  fileStorage.savedFiles.contains(rawDataFilename)
                      ? Icons.check
                      : Icons.data_object,
                ),
                label: Text(
                  usesFolder ? 'Zapisz dane surowe' : 'Pobierz dane surowe',
                ),
              ),
            ),
          ],
        ),
        if (fileStorage.errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            fileStorage.errorMessage!,
            style: const TextStyle(
              color: AppColors.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _selectDirectory(String patientId) async {
    final selected = await fileStorage.pickBaseDirectory();
    if (selected) {
      await fileStorage.preparePatientDirectory(patientId);
    }
  }

  Future<void> _save(Uri uri, String filename) async {
    if (fileStorage.isSupported) {
      await fileStorage.saveDownload(uri, filename);
    } else {
      _download(uri, filename);
    }
  }

  void _download(Uri uri, String filename) {
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = uri.toString();
    anchor.download = filename;
    anchor.click();
  }
}

class _EventsCard extends StatelessWidget {
  final List<SessionEvent> events;

  const _EventsCard({required this.events});

  @override
  Widget build(BuildContext context) {
    return _SummaryCard(
      title: 'Zdarzenia obserwowane',
      icon: Icons.event_note,
      children: events.map((event) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 62,
                child: Text(
                  _formatElapsedMs(event.elapsedMs),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.label,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (event.note.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        event.note,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                _formatCategory(event.category),
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SummaryCard({
    required this.title,
    required this.icon,
    required this.children,
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
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: AppColors.text)),
          ),
          Text(
            value.toString(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime? value) {
  if (value == null) return '-';
  return value.toLocal().toString().split('.').first;
}

String _formatDuration(Duration? value) {
  if (value == null) return '-';
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

String _formatElapsedMs(int elapsedMs) {
  final duration = Duration(milliseconds: elapsedMs);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String _formatCategory(String value) {
  return switch (value) {
    'patient_behavior' => 'Zachowanie pacjenta',
    'patient_response' => 'Reakcja pacjenta',
    'task' => 'Zadanie',
    'support' => 'Wsparcie',
    'custom' => 'Własne',
    _ => value,
  };
}
