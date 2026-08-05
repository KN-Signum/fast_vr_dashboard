import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vr_fast_dashboard/providers/session_provider.dart';
import 'package:vr_fast_dashboard/services/session_api.dart';
import 'package:vr_fast_dashboard/widgets/post_session_notes_dialog.dart';

void main() {
  testWidgets('ends the session and saves post-session notes', (tester) async {
    final api = _DialogSessionApi();
    final provider = SessionProvider(api: api);
    await provider.restoreActiveSession();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => PostSessionNotesDialog(session: provider),
              ),
              child: const Text('End'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();

    expect(api.ended, isTrue);
    expect(provider.stage, SessionStage.summary);
    expect(
      find.byKey(const ValueKey('post-session-notes-field')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('post-session-notes-field')),
      'Patient felt well',
    );
    await tester.tap(find.byKey(const ValueKey('save-post-session-notes')));
    await tester.pumpAndSettle();

    expect(api.savedNotes, 'Patient felt well');
    expect(provider.postSessionNotes, 'Patient felt well');
    expect(find.byType(PostSessionNotesDialog), findsNothing);
  });
}

class _DialogSessionApi implements SessionApi {
  bool ended = false;
  String? savedNotes;

  @override
  Future<Map<String, dynamic>?> activeSession() async => _summary('active');

  @override
  Future<Map<String, dynamic>?> recoveredSession() async => null;

  @override
  Future<Map<String, dynamic>> endSession(String sessionId) async {
    ended = true;
    return _summary('completed');
  }

  @override
  Future<Map<String, dynamic>> updatePostSessionNotes({
    required String sessionId,
    required String notes,
  }) async {
    savedNotes = notes;
    return _summary('completed', postSessionNotes: notes);
  }

  @override
  Future<Map<String, dynamic>> createSession({
    required String patientId,
    required String preferredHand,
    required String notes,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> addEvent({
    required String sessionId,
    required String label,
    required String category,
    required String note,
  }) => throw UnimplementedError();

  @override
  Uri rawDownloadUri(String sessionId) => Uri();

  @override
  Uri summaryDownloadUri(String sessionId) => Uri();

  @override
  void close() {}

  Map<String, dynamic> _summary(String status, {String postSessionNotes = ''}) {
    return {
      'session_id': 'session-001',
      'patient_id': 'patient-001',
      'preferred_hand': 'right',
      'notes': 'Baseline',
      'post_session_notes': postSessionNotes,
      'status': status,
      'started_at': '2026-01-02T03:04:05Z',
      'ended_at': status == 'active' ? null : '2026-01-02T03:05:05Z',
      'duration_seconds': status == 'active' ? 0.0 : 60.0,
      'counts': <String, dynamic>{},
      'dropped_records': 0,
      'session_events': <Map<String, dynamic>>[],
    };
  }
}
