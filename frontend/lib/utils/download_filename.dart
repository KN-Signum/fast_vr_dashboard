String safeFilenamePart(String value, {required String fallback}) {
  final sanitized = value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');
  return sanitized.isEmpty ? fallback : sanitized;
}

String sessionReportFilename(String patientId, String sessionId) {
  final patient = safeFilenamePart(patientId, fallback: 'pacjent');
  final session = safeFilenamePart(sessionId, fallback: 'sesja');
  return 'raport_sesji_${patient}_$session.pdf';
}

String sessionRawDataFilename(String patientId, String sessionId) {
  final patient = safeFilenamePart(patientId, fallback: 'pacjent');
  final session = safeFilenamePart(sessionId, fallback: 'sesja');
  return 'raw_data_${patient}_$session.zip';
}

String paintingFilename(String patientId, int timestamp, String format) {
  final patient = safeFilenamePart(patientId, fallback: 'pacjent');
  final extension = safeFilenamePart(format, fallback: 'png');
  return 'wynik_badania_${patient}_$timestamp.$extension';
}
