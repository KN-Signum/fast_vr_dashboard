import 'dart:convert';

import 'package:flutter/foundation.dart';

enum SessionStage { setup, active, summary }

class RecordedPayload {
  final DateTime receivedAt;
  final Map<String, dynamic> payload;

  RecordedPayload({required this.receivedAt, required this.payload});

  Map<String, dynamic> toJson() => {
    'received_at': receivedAt.toIso8601String(),
    'payload': payload,
  };
}

class VrFrameStat {
  final DateTime receivedAt;
  final int byteLength;

  VrFrameStat({required this.receivedAt, required this.byteLength});

  Map<String, dynamic> toJson() => {
    'received_at': receivedAt.toIso8601String(),
    'byte_length': byteLength,
  };
}

class SessionProvider with ChangeNotifier {
  SessionStage _stage = SessionStage.setup;
  String? _sessionId;
  String _patientId = '';
  String _preferredHand = 'not_specified';
  String _notes = '';
  DateTime? _startedAt;
  DateTime? _endedAt;

  final List<RecordedPayload> _eegRecords = [];
  final List<RecordedPayload> _eyeTrackingRecords = [];
  final List<RecordedPayload> _vrEvents = [];
  final List<VrFrameStat> _vrFrameStats = [];

  SessionStage get stage => _stage;
  String? get sessionId => _sessionId;
  String get patientId => _patientId;
  String get preferredHand => _preferredHand;
  String get notes => _notes;
  DateTime? get startedAt => _startedAt;
  DateTime? get endedAt => _endedAt;

  List<RecordedPayload> get eegRecords => List.unmodifiable(_eegRecords);
  List<RecordedPayload> get eyeTrackingRecords =>
      List.unmodifiable(_eyeTrackingRecords);
  List<RecordedPayload> get vrEvents => List.unmodifiable(_vrEvents);
  List<VrFrameStat> get vrFrameStats => List.unmodifiable(_vrFrameStats);

  bool get isActive => _stage == SessionStage.active;

  Duration? get duration {
    final start = _startedAt;
    if (start == null) return null;
    return (_endedAt ?? DateTime.now()).difference(start);
  }

  void createSession({
    required String patientId,
    required String preferredHand,
    String notes = '',
  }) {
    final trimmedPatientId = patientId.trim();
    if (trimmedPatientId.isEmpty) {
      throw ArgumentError.value(
        patientId,
        'patientId',
        'Patient ID is required',
      );
    }

    final now = DateTime.now();
    _stage = SessionStage.active;
    _sessionId = 'session_${now.millisecondsSinceEpoch}';
    _patientId = trimmedPatientId;
    _preferredHand = preferredHand;
    _notes = notes.trim();
    _startedAt = now;
    _endedAt = null;
    _clearRecords();
    notifyListeners();
  }

  void endSession() {
    if (_stage != SessionStage.active) return;

    _endedAt = DateTime.now();
    _stage = SessionStage.summary;
    notifyListeners();
  }

  void startNewSession() {
    _stage = SessionStage.setup;
    _sessionId = null;
    _patientId = '';
    _preferredHand = 'not_specified';
    _notes = '';
    _startedAt = null;
    _endedAt = null;
    _clearRecords();
    notifyListeners();
  }

  void recordEeg(Map<String, dynamic> payload, {DateTime? receivedAt}) {
    if (!isActive) return;
    _eegRecords.add(
      RecordedPayload(
        receivedAt: receivedAt ?? DateTime.now(),
        payload: _copyPayload(payload),
      ),
    );
    notifyListeners();
  }

  void recordEyeTracking(Map<String, dynamic> payload, {DateTime? receivedAt}) {
    if (!isActive) return;
    _eyeTrackingRecords.add(
      RecordedPayload(
        receivedAt: receivedAt ?? DateTime.now(),
        payload: _copyPayload(payload),
      ),
    );
    notifyListeners();
  }

  void recordVrEvent(Map<String, dynamic> payload, {DateTime? receivedAt}) {
    if (!isActive) return;
    _vrEvents.add(
      RecordedPayload(
        receivedAt: receivedAt ?? DateTime.now(),
        payload: _copyPayload(payload),
      ),
    );
    notifyListeners();
  }

  void recordVrJsonMessage(String message, {DateTime? receivedAt}) {
    if (!isActive) return;
    try {
      final decoded = json.decode(message);
      if (decoded is! Map<String, dynamic>) return;

      final type = decoded['type'];
      if (type == 'eeg_data' || type == 'eye_tracking') return;

      recordVrEvent(decoded, receivedAt: receivedAt);
    } catch (_) {
      return;
    }
  }

  void recordVrFrame(int byteLength, {DateTime? receivedAt}) {
    if (!isActive) return;
    _vrFrameStats.add(
      VrFrameStat(
        receivedAt: receivedAt ?? DateTime.now(),
        byteLength: byteLength,
      ),
    );
    notifyListeners();
  }

  Map<String, dynamic> summaryReport() {
    final durationValue = duration;
    return {
      'session_id': _sessionId,
      'patient_id': _patientId,
      'preferred_hand': _preferredHand,
      'notes': _notes,
      'started_at': _startedAt?.toIso8601String(),
      'ended_at': _endedAt?.toIso8601String(),
      'duration_seconds': durationValue == null
          ? null
          : durationValue.inMilliseconds / 1000.0,
      'counts': {
        'eeg_records': _eegRecords.length,
        'eye_tracking_records': _eyeTrackingRecords.length,
        'vr_events': _vrEvents.length,
        'vr_frames': _vrFrameStats.length,
      },
    };
  }

  Map<String, dynamic> rawData() => {
    'summary': summaryReport(),
    'eeg_records': _eegRecords.map((record) => record.toJson()).toList(),
    'eye_tracking_records': _eyeTrackingRecords
        .map((record) => record.toJson())
        .toList(),
    'vr_events': _vrEvents.map((record) => record.toJson()).toList(),
    'vr_frame_stats': _vrFrameStats.map((record) => record.toJson()).toList(),
  };

  Map<String, dynamic> _copyPayload(Map<String, dynamic> payload) {
    return json.decode(json.encode(payload)) as Map<String, dynamic>;
  }

  void _clearRecords() {
    _eegRecords.clear();
    _eyeTrackingRecords.clear();
    _vrEvents.clear();
    _vrFrameStats.clear();
  }
}
