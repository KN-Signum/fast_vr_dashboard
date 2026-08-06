import 'package:flutter_test/flutter_test.dart';
import 'package:vr_fast_dashboard/utils/download_filename.dart';

void main() {
  test('session downloads include normalized patient and session IDs', () {
    expect(
      sessionReportFilename(' patient/01 ', 'session-123'),
      'raport_sesji_patient_01_session-123.pdf',
    );
    expect(
      sessionRawDataFilename(' patient/01 ', 'session-123'),
      'raw_data_patient_01_session-123.zip',
    );
  });

  test('painting filename includes patient ID and timestamp', () {
    expect(
      paintingFilename('patient-01', 123456, 'jpg'),
      'wynik_badania_patient-01_123456.jpg',
    );
  });

  test('filename parts use a fallback when no safe characters remain', () {
    expect(
      sessionReportFilename('///', '...'),
      'raport_sesji_pacjent_sesja.pdf',
    );
  });
}
