import 'package:flutter/foundation.dart';

import '../services/session_api.dart';

enum SessionStage { loading, setup, active, summary }

class SessionEvent {
  final String id;
  final String label;
  final String category;
  final String note;
  final DateTime occurredAt;
  final int elapsedMs;
  final String source;

  SessionEvent({
    required this.id,
    required this.label,
    required this.category,
    required this.note,
    required this.occurredAt,
    required this.elapsedMs,
    required this.source,
  });

  factory SessionEvent.fromJson(Map<String, dynamic> json) {
    return SessionEvent(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      category: json['category'] as String? ?? '',
      note: json['note'] as String? ?? '',
      occurredAt: DateTime.parse(json['occurred_at'] as String),
      elapsedMs: (json['elapsed_ms'] as num?)?.toInt() ?? 0,
      source: json['source'] as String? ?? 'clinician',
    );
  }
}

class SessionProvider with ChangeNotifier {
  final SessionApi _api;

  SessionStage _stage = SessionStage.loading;
  String? _sessionId;
  String _patientId = '';
  String _preferredHand = 'not_specified';
  String _notes = '';
  String _postSessionNotes = '';
  String _status = '';
  DateTime? _startedAt;
  DateTime? _endedAt;
  Map<String, dynamic> _summary = {};
  List<SessionEvent> _sessionEvents = [];
  bool _isBusy = false;
  String? _errorMessage;
  bool _isRawUploadBusy = false;
  bool _rawUploadCompleted = false;
  String? _rawUploadError;

  SessionProvider({required SessionApi api}) : _api = api;

  SessionStage get stage => _stage;
  String? get sessionId => _sessionId;
  String get patientId => _patientId;
  String get preferredHand => _preferredHand;
  String get notes => _notes;
  String get postSessionNotes => _postSessionNotes;
  String get status => _status;
  DateTime? get startedAt => _startedAt;
  DateTime? get endedAt => _endedAt;
  List<SessionEvent> get sessionEvents => List.unmodifiable(_sessionEvents);
  bool get isActive => _stage == SessionStage.active;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  bool get isRawUploadBusy => _isRawUploadBusy;
  bool get rawUploadCompleted => _rawUploadCompleted;
  String? get rawUploadError => _rawUploadError;

  Duration? get duration {
    final start = _startedAt;
    if (start == null) return null;
    return (_endedAt ?? DateTime.now()).difference(start);
  }

  Uri? get summaryDownloadUri {
    final id = _sessionId;
    return id == null ? null : _api.summaryDownloadUri(id);
  }

  Uri? get rawDownloadUri {
    final id = _sessionId;
    return id == null ? null : _api.rawDownloadUri(id);
  }

  Future<void> restoreActiveSession() async {
    _stage = SessionStage.loading;
    _errorMessage = null;
    notifyListeners();
    try {
      final active = await _api.activeSession();
      if (active == null) {
        final recovered = await _api.recoveredSession();
        if (recovered == null) {
          _stage = SessionStage.setup;
        } else {
          _applySummary(recovered, stage: SessionStage.summary);
        }
      } else {
        _applySummary(active, stage: SessionStage.active);
      }
    } on SessionApiException catch (error) {
      _errorMessage = error.message;
      _stage = SessionStage.setup;
    } finally {
      notifyListeners();
    }
  }

  Future<bool> createSession({
    required String patientId,
    required String preferredHand,
    String notes = '',
  }) async {
    final trimmedPatientId = patientId.trim();
    if (trimmedPatientId.isEmpty) {
      _errorMessage = 'ID pacjenta jest wymagane';
      notifyListeners();
      return false;
    }

    return _runOperation(() async {
      final summary = await _api.createSession(
        patientId: trimmedPatientId,
        preferredHand: preferredHand,
        notes: notes.trim(),
      );
      _applySummary(summary, stage: SessionStage.active);
    });
  }

  Future<bool> endSession() async {
    final id = _sessionId;
    if (!isActive || id == null) return false;
    return _runOperation(() async {
      final summary = await _api.endSession(id);
      _applySummary(summary, stage: SessionStage.summary);
    });
  }

  Future<bool> updatePostSessionNotes(String notes) async {
    final id = _sessionId;
    if (_stage != SessionStage.summary || id == null) return false;
    return _runOperation(() async {
      final summary = await _api.updatePostSessionNotes(
        sessionId: id,
        notes: notes.trim(),
      );
      _applySummary(summary, stage: SessionStage.summary);
    });
  }

  Future<bool> addClinicianEvent({
    required String label,
    required String category,
    String note = '',
  }) async {
    final id = _sessionId;
    final trimmedLabel = label.trim();
    if (!isActive || id == null || trimmedLabel.isEmpty) return false;

    return _runOperation(() async {
      final event = await _api.addEvent(
        sessionId: id,
        label: trimmedLabel,
        category: category,
        note: note.trim(),
      );
      _sessionEvents = [..._sessionEvents, SessionEvent.fromJson(event)]
        ..sort((left, right) => left.elapsedMs.compareTo(right.elapsedMs));
      _updateEventSummary();
    }, exposeBusyState: false);
  }

  Future<bool> uploadRawData() async {
    final id = _sessionId;
    if (_stage != SessionStage.summary ||
        id == null ||
        _isRawUploadBusy ||
        _rawUploadCompleted) {
      return false;
    }

    _isRawUploadBusy = true;
    _rawUploadError = null;
    notifyListeners();
    try {
      await _api.uploadRawData(id);
      _rawUploadCompleted = true;
      return true;
    } on SessionApiException catch (error) {
      _rawUploadError = error.message;
      return false;
    } finally {
      _isRawUploadBusy = false;
      notifyListeners();
    }
  }

  void startNewSession() {
    _stage = SessionStage.setup;
    _sessionId = null;
    _patientId = '';
    _preferredHand = 'not_specified';
    _notes = '';
    _postSessionNotes = '';
    _status = '';
    _startedAt = null;
    _endedAt = null;
    _summary = {};
    _sessionEvents = [];
    _errorMessage = null;
    _isRawUploadBusy = false;
    _rawUploadCompleted = false;
    _rawUploadError = null;
    notifyListeners();
  }

  Map<String, dynamic> summaryReport() => Map<String, dynamic>.from(_summary);

  Future<bool> _runOperation(
    Future<void> Function() operation, {
    bool exposeBusyState = true,
  }) async {
    if (_isBusy && exposeBusyState) return false;
    if (exposeBusyState) _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await operation();
      return true;
    } on SessionApiException catch (error) {
      _errorMessage = error.message;
      return false;
    } finally {
      if (exposeBusyState) _isBusy = false;
      notifyListeners();
    }
  }

  void _applySummary(
    Map<String, dynamic> summary, {
    required SessionStage stage,
  }) {
    final previousSessionId = _sessionId;
    final nextSessionId = summary['session_id'] as String?;
    if (previousSessionId != nextSessionId) {
      _isRawUploadBusy = false;
      _rawUploadCompleted = false;
      _rawUploadError = null;
    }
    _summary = Map<String, dynamic>.from(summary);
    _sessionId = nextSessionId;
    _patientId = summary['patient_id'] as String? ?? '';
    _preferredHand = summary['preferred_hand'] as String? ?? 'not_specified';
    _notes = summary['notes'] as String? ?? '';
    _postSessionNotes = summary['post_session_notes'] as String? ?? '';
    _status = summary['status'] as String? ?? '';
    _startedAt = _parseDate(summary['started_at']);
    _endedAt = _parseDate(summary['ended_at']);
    final events = summary['session_events'];
    _sessionEvents = events is List
        ? events
              .whereType<Map>()
              .map(
                (event) =>
                    SessionEvent.fromJson(Map<String, dynamic>.from(event)),
              )
              .toList()
        : [];
    _stage = stage;
  }

  void _updateEventSummary() {
    final counts = Map<String, dynamic>.from(
      _summary['counts'] as Map? ?? const {},
    );
    counts['session_events'] = _sessionEvents.length;
    _summary['counts'] = counts;
    _summary['session_events'] = _sessionEvents
        .map(
          (event) => {
            'id': event.id,
            'label': event.label,
            'category': event.category,
            'note': event.note,
            'occurred_at': event.occurredAt.toIso8601String(),
            'elapsed_ms': event.elapsedMs,
            'source': event.source,
          },
        )
        .toList();
  }

  DateTime? _parseDate(dynamic value) {
    return value is String && value.isNotEmpty ? DateTime.parse(value) : null;
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }
}
