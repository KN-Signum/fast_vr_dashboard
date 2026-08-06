import 'dart:typed_data';

import 'session_file_store.dart';

SessionFileStore createPlatformSessionFileStore() => _UnsupportedFileStore();

class _UnsupportedFileStore implements SessionFileStore {
  @override
  bool get isSupported => false;

  @override
  String? get baseDirectoryName => null;

  @override
  String? get patientDirectoryName => null;

  @override
  Future<void> pickBaseDirectory() async {
    throw UnsupportedError('Directory picker is not supported');
  }

  @override
  Future<void> preparePatientDirectory(String directoryName) async {
    throw UnsupportedError('Directory picker is not supported');
  }

  @override
  Future<void> writeFile(String filename, Uint8List bytes) async {
    throw UnsupportedError('Directory picker is not supported');
  }

  @override
  void clear() {}
}
