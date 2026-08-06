@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:vr_fast_dashboard/providers/session_file_storage_provider.dart';
import 'package:vr_fast_dashboard/providers/session_provider.dart';
import 'package:vr_fast_dashboard/screens/session_summary_screen.dart';
import 'package:vr_fast_dashboard/services/session_api.dart';
import 'package:vr_fast_dashboard/services/session_file_store.dart';
import 'package:vr_fast_dashboard/theme/app_style.dart';

void main() {
  testWidgets('places session files below patient details on desktop', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1200, 1200));
    await _pumpSummary(tester);

    final patient = tester.getTopLeft(find.text('Pacjent'));
    final files = tester.getTopLeft(find.text('Pliki sesji'));
    final counts = tester.getTopLeft(find.text('Zarejestrowane dane'));
    final filesPanel = tester.getRect(
      find.ancestor(
        of: find.text('Pliki sesji'),
        matching: find.byType(SectionPanel),
      ),
    );
    final countsPanel = tester.getRect(
      find.ancestor(
        of: find.text('Zarejestrowane dane'),
        matching: find.byType(SectionPanel),
      ),
    );

    expect(files.dx, closeTo(patient.dx, 1));
    expect(files.dy, greaterThan(patient.dy));
    expect(counts.dx, greaterThan(patient.dx));
    expect((filesPanel.bottom - countsPanel.bottom).abs(), lessThan(24));
    expect(find.text('Notatka przed testem'), findsNothing);
    expect(find.text('Notatka po teście'), findsNothing);
  });

  testWidgets('uses one column and stacks save buttons on narrow screens', (
    tester,
  ) async {
    await _setViewport(tester, const Size(400, 1600));
    await _pumpSummary(tester);

    final patient = tester.getTopLeft(find.text('Pacjent'));
    final files = tester.getTopLeft(find.text('Pliki sesji'));
    final counts = tester.getTopLeft(find.text('Zarejestrowane dane'));
    final reportButton = tester.getTopLeft(find.text('Raport PDF'));
    final rawDataButton = tester.getTopLeft(find.text('Dane ZIP'));

    expect(files.dy, greaterThan(patient.dy));
    expect(counts.dy, greaterThan(files.dy));
    expect(rawDataButton.dy, greaterThan(reportButton.dy));
  });

  testWidgets('confirms a successful local report save', (tester) async {
    await _setViewport(tester, const Size(1200, 1200));
    await _pumpSummary(tester);

    await tester.tap(find.text('Raport PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Raport PDF zapisano pomyślnie.'), findsOneWidget);
  });
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Future<void> _pumpSummary(WidgetTester tester) async {
  final session = SessionProvider(api: _SummarySessionApi());
  final fileStorage = SessionFileStorageProvider(
    store: _ReadyFileStore(),
    httpClient: MockClient((_) async => http.Response('file', 200)),
  );
  await session.restoreActiveSession();
  addTearDown(session.dispose);
  addTearDown(fileStorage.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: fileStorage),
      ],
      child: const MaterialApp(home: SessionSummaryScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

class _SummarySessionApi implements SessionApi {
  @override
  Future<Map<String, dynamic>?> activeSession() async => null;

  @override
  Future<Map<String, dynamic>?> recoveredSession() async => {
    'session_id': 'session-001',
    'patient_id': 'patient-001',
    'preferred_hand': 'right',
    'notes': 'Notatka przed testem',
    'post_session_notes': 'Notatka po teście',
    'status': 'completed',
    'started_at': '2026-01-02T03:04:05Z',
    'ended_at': '2026-01-02T03:05:05Z',
    'duration_seconds': 60.0,
    'counts': {
      'eeg_records': 100,
      'eye_tracking_records': 200,
      'vr_events': 5,
      'vr_frames': 50,
      'session_events': 0,
    },
    'dropped_records': 0,
    'eye_tracking_analysis': null,
    'session_events': <Map<String, dynamic>>[],
  };

  @override
  Future<Map<String, dynamic>> addEvent({
    required String sessionId,
    required String label,
    required String category,
    required String note,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> createSession({
    required String patientId,
    required String preferredHand,
    required String notes,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> endSession(String sessionId) =>
      throw UnimplementedError();

  @override
  Uri rawDownloadUri(String sessionId) =>
      Uri.parse('http://localhost/download/raw');

  @override
  Uri summaryDownloadUri(String sessionId) =>
      Uri.parse('http://localhost/download/summary');

  @override
  Future<Map<String, dynamic>> updatePostSessionNotes({
    required String sessionId,
    required String notes,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> uploadRawData(String sessionId) async => {
    'uploaded': true,
  };

  @override
  void close() {}
}

class _ReadyFileStore implements SessionFileStore {
  @override
  String? get baseDirectoryName => 'League of Legends';

  @override
  bool get isSupported => true;

  @override
  String? get patientDirectoryName => 'patient-001';

  @override
  void clear() {}

  @override
  Future<void> pickBaseDirectory() => throw UnimplementedError();

  @override
  Future<void> preparePatientDirectory(String directoryName) =>
      throw UnimplementedError();

  @override
  Future<void> writeFile(String filename, Uint8List bytes) async {}
}
