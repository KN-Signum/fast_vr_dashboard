import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vr_fast_dashboard/providers/session_file_storage_provider.dart';
import 'package:vr_fast_dashboard/services/session_file_store.dart';

void main() {
  test('selects a base folder and creates a safe patient directory', () async {
    final store = _FakeFileStore();
    final provider = SessionFileStorageProvider(store: store);

    expect(await provider.pickBaseDirectory(), isTrue);
    expect(provider.baseDirectoryName, 'Badania');
    expect(await provider.preparePatientDirectory(' patient/01 '), isTrue);
    expect(provider.patientDirectoryName, 'patient_01');

    provider.dispose();
  });

  test('saves final report and raw data into the patient directory', () async {
    final store = _FakeFileStore();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/summary')) {
        return http.Response.bytes([1, 2, 3], 200);
      }
      return http.Response.bytes([4, 5, 6], 200);
    });
    final provider = SessionFileStorageProvider(
      store: store,
      httpClient: client,
    );
    await provider.pickBaseDirectory();
    await provider.preparePatientDirectory('patient-01');

    final saved = await provider.saveSessionDeliverables(
      reportUri: Uri.parse('http://localhost/download/summary'),
      reportFilename: 'report.pdf',
      rawDataUri: Uri.parse('http://localhost/download/raw'),
      rawDataFilename: 'raw.zip',
    );

    expect(saved, isTrue);
    expect(store.files['report.pdf'], Uint8List.fromList([1, 2, 3]));
    expect(store.files['raw.zip'], Uint8List.fromList([4, 5, 6]));
    expect(provider.savedFiles, {'report.pdf', 'raw.zip'});

    provider.dispose();
  });

  test('does not report cancellation as a storage error', () async {
    final store = _FakeFileStore(cancelSelection: true);
    final provider = SessionFileStorageProvider(store: store);

    expect(await provider.pickBaseDirectory(), isFalse);
    expect(provider.errorMessage, isNull);

    provider.dispose();
  });
}

class _FakeFileStore implements SessionFileStore {
  _FakeFileStore({this.cancelSelection = false});

  final bool cancelSelection;
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
    if (cancelSelection) throw const DirectorySelectionCancelled();
    _baseDirectoryName = 'Badania';
    _patientDirectoryName = null;
  }

  @override
  Future<void> preparePatientDirectory(String directoryName) async {
    if (_baseDirectoryName == null) throw StateError('No base directory');
    _patientDirectoryName = directoryName;
  }

  @override
  Future<void> writeFile(String filename, Uint8List bytes) async {
    if (_patientDirectoryName == null) {
      throw StateError('No patient directory');
    }
    files[filename] = Uint8List.fromList(bytes);
  }

  @override
  void clear() {
    _baseDirectoryName = null;
    _patientDirectoryName = null;
    files.clear();
  }
}
