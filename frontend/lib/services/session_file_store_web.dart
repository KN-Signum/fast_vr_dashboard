import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'session_file_store.dart';

@JS()
extension type _DirectoryPickerOptions._(JSObject _) implements JSObject {
  external factory _DirectoryPickerOptions({String mode});
}

@JS('showDirectoryPicker')
external JSPromise<web.FileSystemDirectoryHandle> _showDirectoryPicker(
  _DirectoryPickerOptions options,
);

SessionFileStore createPlatformSessionFileStore() => _WebSessionFileStore();

class _WebSessionFileStore implements SessionFileStore {
  web.FileSystemDirectoryHandle? _baseDirectory;
  web.FileSystemDirectoryHandle? _patientDirectory;

  @override
  bool get isSupported {
    return web.window.isSecureContext &&
        web.window.hasProperty('showDirectoryPicker'.toJS).toDart;
  }

  @override
  String? get baseDirectoryName => _baseDirectory?.name;

  @override
  String? get patientDirectoryName => _patientDirectory?.name;

  @override
  Future<void> pickBaseDirectory() async {
    try {
      _baseDirectory = await _showDirectoryPicker(
        _DirectoryPickerOptions(mode: 'readwrite'),
      ).toDart;
      _patientDirectory = null;
    } catch (error) {
      if (error.toString().contains('AbortError')) {
        throw const DirectorySelectionCancelled();
      }
      rethrow;
    }
  }

  @override
  Future<void> preparePatientDirectory(String directoryName) async {
    final baseDirectory = _baseDirectory;
    if (baseDirectory == null) {
      throw StateError('Base directory has not been selected');
    }
    _patientDirectory = await baseDirectory
        .getDirectoryHandle(
          directoryName,
          web.FileSystemGetDirectoryOptions(create: true),
        )
        .toDart;
  }

  @override
  Future<void> writeFile(String filename, Uint8List bytes) async {
    final patientDirectory = _patientDirectory;
    if (patientDirectory == null) {
      throw StateError('Patient directory has not been prepared');
    }
    final file = await patientDirectory
        .getFileHandle(filename, web.FileSystemGetFileOptions(create: true))
        .toDart;
    final writable = await file.createWritable().toDart;
    await writable.write(bytes.toJS).toDart;
    await writable.close().toDart;
  }

  @override
  void clear() {
    _baseDirectory = null;
    _patientDirectory = null;
  }
}
