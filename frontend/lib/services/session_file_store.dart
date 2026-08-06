import 'dart:typed_data';

abstract interface class SessionFileStore {
  bool get isSupported;
  String? get baseDirectoryName;
  String? get patientDirectoryName;

  Future<void> pickBaseDirectory();

  Future<void> preparePatientDirectory(String directoryName);

  Future<void> writeFile(String filename, Uint8List bytes);

  void clear();
}

class DirectorySelectionCancelled implements Exception {
  const DirectorySelectionCancelled();
}
