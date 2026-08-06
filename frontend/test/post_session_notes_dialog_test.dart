import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vr_fast_dashboard/providers/session_file_storage_provider.dart';
import 'package:vr_fast_dashboard/providers/session_provider.dart';
import 'package:vr_fast_dashboard/services/session_api.dart';
import 'package:vr_fast_dashboard/services/session_file_store.dart';
import 'package:vr_fast_dashboard/widgets/post_session_notes_dialog.dart';

void main() {
  testWidgets('ends the session and saves post-session notes', (tester) async {
    final api = _DialogSessionApi();
    final provider = SessionProvider(api: api);
    final fileStore = _DialogFileStore();
    final fileStorage = SessionFileStorageProvider(
      store: fileStore,
      httpClient: MockClient((request) async {
        return http.Response.bytes(
          request.url.path.endsWith('/summary') ? [1, 2] : [3, 4],
          200,
        );
      }),
    );
    await provider.restoreActiveSession();
    await fileStorage.pickBaseDirectory();
    await fileStorage.preparePatientDirectory(provider.patientId);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => PostSessionNotesDialog(
                  session: provider,
                  fileStorage: fileStorage,
                ),
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
    expect(
      fileStore.files.keys,
      containsAll([
        'raport_sesji_patient-001_session-001.pdf',
        'raw_data_patient-001_session-001.zip',
      ]),
    );
    expect(find.byType(PostSessionNotesDialog), findsNothing);

    fileStorage.dispose();
    provider.dispose();
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
  Future<Map<String, dynamic>> uploadRawData(String sessionId) =>
      throw UnimplementedError();

  @override
  Uri rawDownloadUri(String sessionId) =>
      Uri.parse('http://localhost/download/raw');

  @override
  Uri summaryDownloadUri(String sessionId) =>
      Uri.parse('http://localhost/download/summary');

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

class _DialogFileStore implements SessionFileStore {
  final Map<String, Uint8List> files = {};
  String? _baseDirectoryName;
  String? _patientDirectoryName;

  @override
  bool get isSupported => true;

  @override
  String? get baseDirectoryName => _baseDirectoryName;

  @override
  String? get patientDirectoryName => _patientDirectoryName;

  @override
  Future<void> pickBaseDirectory() async {
    _baseDirectoryName = 'Badania';
  }

  @override
  Future<void> preparePatientDirectory(String directoryName) async {
    _patientDirectoryName = directoryName;
  }

  @override
  Future<void> writeFile(String filename, Uint8List bytes) async {
    files[filename] = Uint8List.fromList(bytes);
  }

  @override
  void clear() {
    _baseDirectoryName = null;
    _patientDirectoryName = null;
    files.clear();
  }
}
