import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../services/session_file_store.dart';
import '../utils/download_filename.dart';

class SessionFileStorageProvider with ChangeNotifier {
  SessionFileStorageProvider({
    required SessionFileStore store,
    http.Client? httpClient,
  }) : _store = store,
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final SessionFileStore _store;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Set<String> _savedFiles = {};

  bool _isBusy = false;
  String? _errorMessage;

  bool get isSupported => _store.isSupported;
  bool get isBusy => _isBusy;
  bool get hasBaseDirectory => _store.baseDirectoryName != null;
  bool get hasPatientDirectory => _store.patientDirectoryName != null;
  String? get baseDirectoryName => _store.baseDirectoryName;
  String? get patientDirectoryName => _store.patientDirectoryName;
  String? get errorMessage => _errorMessage;
  Set<String> get savedFiles => Set.unmodifiable(_savedFiles);

  Future<bool> pickBaseDirectory() async {
    if (!isSupported || _isBusy) return false;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _store.pickBaseDirectory();
      _savedFiles.clear();
      return true;
    } on DirectorySelectionCancelled {
      return false;
    } catch (error) {
      _errorMessage = 'Nie udało się wybrać folderu: $error';
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<bool> preparePatientDirectory(String patientId) async {
    if (!hasBaseDirectory || _isBusy) return false;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final directoryName = safeFilenamePart(patientId, fallback: 'pacjent');
      await _store.preparePatientDirectory(directoryName);
      return true;
    } catch (error) {
      _errorMessage = 'Nie udało się utworzyć folderu pacjenta: $error';
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<bool> saveBytes(String filename, Uint8List bytes) {
    return _saveFiles(() async {
      await _store.writeFile(filename, bytes);
      _savedFiles.add(filename);
    });
  }

  Future<bool> saveDownload(Uri uri, String filename) {
    return _saveFiles(() async {
      final response = await _httpClient.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('serwer zwrócił kod ${response.statusCode}');
      }
      await _store.writeFile(filename, response.bodyBytes);
      _savedFiles.add(filename);
    });
  }

  Future<bool> saveSessionDeliverables({
    required Uri reportUri,
    required String reportFilename,
    required Uri rawDataUri,
    required String rawDataFilename,
  }) {
    return _saveFiles(() async {
      final report = await _httpClient.get(reportUri);
      if (report.statusCode < 200 || report.statusCode >= 300) {
        throw StateError('nie udało się pobrać raportu (${report.statusCode})');
      }
      await _store.writeFile(reportFilename, report.bodyBytes);
      _savedFiles.add(reportFilename);

      final rawData = await _httpClient.get(rawDataUri);
      if (rawData.statusCode < 200 || rawData.statusCode >= 300) {
        throw StateError(
          'nie udało się pobrać danych surowych (${rawData.statusCode})',
        );
      }
      await _store.writeFile(rawDataFilename, rawData.bodyBytes);
      _savedFiles.add(rawDataFilename);
    });
  }

  Future<bool> _saveFiles(Future<void> Function() operation) async {
    if (!hasPatientDirectory || _isBusy) {
      if (!hasPatientDirectory) {
        _errorMessage = 'Najpierw wybierz folder zapisu dla tej sesji.';
        notifyListeners();
      }
      return false;
    }
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await operation();
      return true;
    } catch (error) {
      _errorMessage = 'Nie udało się zapisać plików: $error';
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void clear() {
    _store.clear();
    _savedFiles.clear();
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_ownsHttpClient) _httpClient.close();
    super.dispose();
  }
}
