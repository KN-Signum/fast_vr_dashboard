import 'package:flutter_test/flutter_test.dart';
import 'package:vr_fast_dashboard/providers/session_provider.dart';

void main() {
  group('SessionProvider', () {
    test('creating a session stores metadata and start time', () {
      final provider = SessionProvider();

      provider.createSession(
        patientId: ' patient-001 ',
        preferredHand: 'right',
        notes: 'Test notes',
      );

      expect(provider.stage, SessionStage.active);
      expect(provider.sessionId, isNotNull);
      expect(provider.patientId, 'patient-001');
      expect(provider.preferredHand, 'right');
      expect(provider.notes, 'Test notes');
      expect(provider.startedAt, isNotNull);
      expect(provider.endedAt, isNull);
    });

    test('recording only occurs while session is active', () {
      final provider = SessionProvider();

      provider.recordEeg({'type': 'eeg_data'});
      provider.recordEyeTracking({'type': 'eye_tracking'});
      provider.recordVrEvent({'type': 'state_update'});
      provider.recordVrFrame(123);

      expect(provider.eegRecords, isEmpty);
      expect(provider.eyeTrackingRecords, isEmpty);
      expect(provider.vrEvents, isEmpty);
      expect(provider.vrFrameStats, isEmpty);

      provider.createSession(patientId: 'patient-001', preferredHand: 'left');

      provider.recordEeg({'type': 'eeg_data'});
      provider.recordEyeTracking({'type': 'eye_tracking'});
      provider.recordVrEvent({'type': 'state_update'});
      provider.recordVrFrame(123);

      expect(provider.eegRecords, hasLength(1));
      expect(provider.eyeTrackingRecords, hasLength(1));
      expect(provider.vrEvents, hasLength(1));
      expect(provider.vrFrameStats, hasLength(1));

      provider.endSession();
      provider.recordEeg({'type': 'eeg_data'});
      provider.recordVrFrame(456);

      expect(provider.eegRecords, hasLength(1));
      expect(provider.vrFrameStats, hasLength(1));
    });

    test('ending a session stores end time and switches to summary', () {
      final provider = SessionProvider();

      provider.createSession(
        patientId: 'patient-001',
        preferredHand: 'ambidextrous',
      );
      provider.endSession();

      expect(provider.stage, SessionStage.summary);
      expect(provider.endedAt, isNotNull);
      expect(provider.duration, isNotNull);
    });

    test('export JSON contains metadata, counts, and raw records', () {
      final provider = SessionProvider();
      final timestamp = DateTime.utc(2026, 1, 2, 3, 4, 5);

      provider.createSession(
        patientId: 'patient-001',
        preferredHand: 'not_specified',
        notes: 'Baseline session',
      );
      provider.recordEeg({
        'type': 'eeg_data',
        'channels': ['O1'],
      }, receivedAt: timestamp);
      provider.recordEyeTracking({
        'type': 'eye_tracking',
        'eyes_position': {'x': 1, 'y': 2, 'z': 3},
      }, receivedAt: timestamp);
      provider.recordVrEvent({
        'type': 'state_update',
        'current_view': 'forest',
      }, receivedAt: timestamp);
      provider.recordVrFrame(2048, receivedAt: timestamp);
      provider.endSession();

      final summary = provider.summaryReport();
      final rawData = provider.rawData();
      final counts = summary['counts'] as Map<String, dynamic>;

      expect(summary['patient_id'], 'patient-001');
      expect(summary['preferred_hand'], 'not_specified');
      expect(summary['notes'], 'Baseline session');
      expect(counts['eeg_records'], 1);
      expect(counts['eye_tracking_records'], 1);
      expect(counts['vr_events'], 1);
      expect(counts['vr_frames'], 1);

      expect(rawData['summary'], summary);
      expect(rawData['eeg_records'], hasLength(1));
      expect(rawData['eye_tracking_records'], hasLength(1));
      expect(rawData['vr_events'], hasLength(1));
      expect(rawData['vr_frame_stats'], hasLength(1));

      final frameStats = rawData['vr_frame_stats'] as List<dynamic>;
      expect(frameStats.first['byte_length'], 2048);
      expect(frameStats.first['received_at'], timestamp.toIso8601String());
    });
  });
}
