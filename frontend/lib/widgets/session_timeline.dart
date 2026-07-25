import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../theme/app_style.dart';

class SessionTimeline extends StatefulWidget {
  const SessionTimeline({super.key});

  @override
  State<SessionTimeline> createState() => _SessionTimelineState();
}

class _SessionTimelineState extends State<SessionTimeline> {
  final _customController = TextEditingController();
  Timer? _timer;

  static const _predefinedEvents = [
    _PredefinedEvent('Dyskomfort', 'patient_behavior'),
    _PredefinedEvent('Nudności', 'patient_behavior'),
    _PredefinedEvent('Skupienie', 'patient_behavior'),
    _PredefinedEvent('Zamknięte oczy', 'patient_behavior'),
    _PredefinedEvent('Werbalne', 'patient_response'),
    _PredefinedEvent('Zadanie', 'task'),
    _PredefinedEvent('Pomoc', 'support'),
    _PredefinedEvent('Przerwa', 'support'),
  ];

  @override
  void initState() {
    super.initState();
    _customController.addListener(_onCustomChanged);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _customController
      ..removeListener(_onCustomChanged)
      ..dispose();
    super.dispose();
  }

  void _onCustomChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final duration = session.duration ?? Duration.zero;
    final window = _timelineWindow(duration);

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          left: BorderSide(color: AppColors.muted),
          right: BorderSide(color: AppColors.muted),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(width: 142, child: _TimeReadout(duration: duration)),
              const SizedBox(width: 18),
              Expanded(
                child: _TimelineTrack(
                  duration: duration,
                  window: window,
                  events: session.sessionEvents,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(child: _EventComposer(controller: _customController)),
        ],
      ),
    );
  }

  Duration _timelineWindow(Duration duration) {
    const minimum = Duration(minutes: 1);
    if (duration <= minimum) return minimum;

    final minutes = (duration.inSeconds / 60).ceil();
    return Duration(minutes: minutes);
  }
}

class _TimeReadout extends StatelessWidget {
  final Duration duration;

  const _TimeReadout({required this.duration});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'CZAS',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _formatDuration(duration),
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 34,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _TimelineTrack extends StatelessWidget {
  final Duration duration;
  final Duration window;
  final List<SessionEvent> events;

  const _TimelineTrack({
    required this.duration,
    required this.window,
    required this.events,
  });

  @override
  Widget build(BuildContext context) {
    final windowMs = math.max(window.inMilliseconds, 1);
    final progress = (duration.inMilliseconds / windowMs).clamp(0.0, 1.0);

    return SizedBox(
      height: 52,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(constraints.maxWidth, 1.0);
          final progressX = progress * width;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 18,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 18,
                child: Container(
                  width: progressX,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.38),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              ...events.map((event) {
                final ratio = (event.elapsedMs / windowMs).clamp(0.0, 1.0);
                return Positioned(
                  left: ratio * width - 7,
                  top: 15,
                  child: _EventMarker(event: event),
                );
              }),
              Positioned(
                left: progressX.clamp(0.0, width) - 9,
                top: 13,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9F0FF),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                bottom: 0,
                child: Text(
                  _formatElapsed(Duration.zero),
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Text(
                  _formatElapsed(window),
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EventMarker extends StatelessWidget {
  final SessionEvent event;

  const _EventMarker({required this.event});

  @override
  Widget build(BuildContext context) {
    final tooltip = [
      event.label,
      'Kategoria: ${_formatCategory(event.category)}',
      'Czas: ${_formatElapsed(Duration(milliseconds: event.elapsedMs))}',
      if (event.note.isNotEmpty) 'Notatka: ${event.note}',
      'Zarejestrowano: ${event.occurredAt.toLocal().toString().split('.').first}',
    ].join('\n');

    return Tooltip(
      message: tooltip,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.surface, width: 2),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.24),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventComposer extends StatelessWidget {
  final TextEditingController controller;

  const _EventComposer({required this.controller});

  @override
  Widget build(BuildContext context) {
    final customText = controller.text.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(
          width: 142,
          child: Padding(
            padding: EdgeInsets.only(top: 24),
            child: Row(
              children: [
                Icon(Icons.add_box, size: 24, color: AppColors.primary),
                SizedBox(width: 10),
                Text(
                  'Zdarzenia',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: _SessionTimelineState._predefinedEvents.map((event) {
                  return ActionChip(
                    label: Text(event.label),
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                    backgroundColor: AppColors.surfaceAlt,
                    side: const BorderSide(color: AppColors.border),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    onPressed: () {
                      unawaited(
                        context.read<SessionProvider>().addClinicianEvent(
                          label: event.label,
                          category: event.category,
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: TextField(
                        controller: controller,
                        decoration: appInputDecoration('Własne zdarzenie...')
                            .copyWith(
                              labelText: null,
                              hintText: 'Własne zdarzenie...',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 11,
                              ),
                            ),
                        onSubmitted: customText.isEmpty
                            ? null
                            : (_) => _addCustomEvent(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: IconButton.outlined(
                      onPressed: customText.isEmpty
                          ? null
                          : () => _addCustomEvent(context),
                      icon: const Icon(Icons.add),
                      tooltip: 'Dodaj własne zdarzenie',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _addCustomEvent(BuildContext context) {
    final label = controller.text.trim();
    if (label.isEmpty) return;

    unawaited(
      context.read<SessionProvider>().addClinicianEvent(
        label: label,
        category: 'custom',
      ),
    );
    controller.clear();
  }
}

class _PredefinedEvent {
  final String label;
  final String category;

  const _PredefinedEvent(this.label, this.category);
}

String _formatDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

String _formatElapsed(Duration value) {
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${value.inHours > 0 ? '${value.inHours}:' : ''}$minutes:$seconds';
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
