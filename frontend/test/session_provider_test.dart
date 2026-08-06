import 'package:flutter_test/flutter_test.dart';
import 'package:vr_fast_dashboard/providers/session_provider.dart';
import 'package:vr_fast_dashboard/services/session_api.dart';

void main() {
  group('SessionProvider', () {
    test('restores an active backend session', () async {
      final api = FakeSessionApi(active: sessionSummary(status: 'active'));
      final provider = SessionProvider(api: api);

      await provider.restoreActiveSession();

      expect(provider.stage, SessionStage.active);
      expect(provider.sessionId, 'session-001');
      expect(provider.patientId, 'patient-001');
      expect(provider.startedAt, isNotNull);
    });

    test('shows setup when the backend has no active session', () async {
      final provider = SessionProvider(api: FakeSessionApi());

      await provider.restoreActiveSession();

      expect(provider.stage, SessionStage.setup);
    });

    test('opens the summary of a recovered interrupted session', () async {
      final provider = SessionProvider(
        api: FakeSessionApi(recovered: sessionSummary(status: 'interrupted')),
      );

      await provider.restoreActiveSession();

      expect(provider.stage, SessionStage.summary);
      expect(provider.status, 'interrupted');
      expect(provider.sessionId, 'session-001');
    });

    test('creates and ends a server-owned session', () async {
      final api = FakeSessionApi();
      final provider = SessionProvider(api: api);
      await provider.restoreActiveSession();

      final created = await provider.createSession(
        patientId: ' patient-001 ',
        preferredHand: 'right',
        notes: 'Baseline',
      );

      expect(created, isTrue);
      expect(api.createdPatientId, 'patient-001');
      expect(provider.stage, SessionStage.active);

      final ended = await provider.endSession();

      expect(ended, isTrue);
      expect(provider.stage, SessionStage.summary);
      expect(provider.summaryReport()['status'], 'completed');
      expect(provider.endedAt, isNotNull);

      final updated = await provider.updatePostSessionNotes(
        ' Patient felt well ',
      );
      expect(updated, isTrue);
      expect(provider.postSessionNotes, 'Patient felt well');
      expect(api.updatedPostSessionNotes, 'Patient felt well');
    });

    test('adds an observed event returned by the backend', () async {
      final provider = SessionProvider(api: FakeSessionApi());
      await provider.restoreActiveSession();
      await provider.createSession(
        patientId: 'patient-001',
        preferredHand: 'left',
      );

      final added = await provider.addClinicianEvent(
        label: 'Przerwa',
        category: 'support',
        note: 'Prośba pacjenta',
      );

      expect(added, isTrue);
      expect(provider.sessionEvents, hasLength(1));
      expect(provider.sessionEvents.first.label, 'Przerwa');
      final counts = provider.summaryReport()['counts'] as Map<String, dynamic>;
      expect(counts['session_events'], 1);
    });

    test('exposes backend errors without changing session stage', () async {
      final provider = SessionProvider(api: FakeSessionApi(failCreate: true));
      await provider.restoreActiveSession();

      final created = await provider.createSession(
        patientId: 'patient-001',
        preferredHand: 'left',
      );

      expect(created, isFalse);
      expect(provider.stage, SessionStage.setup);
      expect(provider.errorMessage, 'Backend unavailable');
    });

    test('uploads raw data only after the session ends', () async {
      final api = FakeSessionApi();
      final provider = SessionProvider(api: api);
      await provider.restoreActiveSession();
      await provider.createSession(
        patientId: 'patient-001',
        preferredHand: 'left',
      );

      expect(await provider.uploadRawData(), isFalse);
      await provider.endSession();
      expect(await provider.uploadRawData(), isTrue);
      expect(api.uploadedSessionId, 'session-001');
      expect(provider.rawUploadCompleted, isTrue);
      expect(await provider.uploadRawData(), isFalse);
    });
  });
}

Map<String, dynamic> sessionSummary({required String status}) {
  return {
    'session_id': 'session-001',
    'patient_id': 'patient-001',
    'preferred_hand': 'right',
    'notes': 'Baseline',
    'post_session_notes': '',
    'status': status,
    'started_at': '2026-01-02T03:04:05Z',
    'ended_at': status == 'active' ? null : '2026-01-02T03:05:05Z',
    'duration_seconds': status == 'active' ? 0.0 : 60.0,
    'counts': {
      'eeg_records': 2,
      'eye_tracking_records': 3,
      'vr_events': 4,
      'vr_frames': 5,
      'session_events': 0,
    },
    'dropped_records': 0,
    'session_events': <Map<String, dynamic>>[],
  };
}

class FakeSessionApi implements SessionApi {
  Map<String, dynamic>? active;
  Map<String, dynamic>? recovered;
  bool failCreate;
  String? createdPatientId;
  String? updatedPostSessionNotes;
  String? uploadedSessionId;

  FakeSessionApi({this.active, this.recovered, this.failCreate = false});

  @override
  Future<Map<String, dynamic>?> activeSession() async => active;

  @override
  Future<Map<String, dynamic>?> recoveredSession() async {
    final value = recovered;
    recovered = null;
    return value;
  }

  @override
  Future<Map<String, dynamic>> createSession({
    required String patientId,
    required String preferredHand,
    required String notes,
  }) async {
    if (failCreate) {
      throw const SessionApiException('Backend unavailable');
    }
    createdPatientId = patientId;
    active = sessionSummary(status: 'active');
    return active!;
  }

  @override
  Future<Map<String, dynamic>> endSession(String sessionId) async {
    active = null;
    return sessionSummary(status: 'completed');
  }

  @override
  Future<Map<String, dynamic>> updatePostSessionNotes({
    required String sessionId,
    required String notes,
  }) async {
    updatedPostSessionNotes = notes;
    final summary = sessionSummary(status: 'completed');
    summary['post_session_notes'] = notes;
    return summary;
  }

  @override
  Future<Map<String, dynamic>> addEvent({
    required String sessionId,
    required String label,
    required String category,
    required String note,
  }) async {
    return {
      'id': 'event-001',
      'label': label,
      'category': category,
      'note': note,
      'occurred_at': '2026-01-02T03:04:10Z',
      'elapsed_ms': 5000,
      'source': 'clinician',
    };
  }

  @override
  Future<Map<String, dynamic>> uploadRawData(String sessionId) async {
    uploadedSessionId = sessionId;
    return {'uploaded': true, 'filename': 'raw.zip'};
  }

  @override
  Uri rawDownloadUri(String sessionId) {
    return Uri.parse('http://localhost/api/sessions/$sessionId/download/raw');
  }

  @override
  Uri summaryDownloadUri(String sessionId) {
    return Uri.parse(
      'http://localhost/api/sessions/$sessionId/download/summary',
    );
  }

  @override
  void close() {}
}
