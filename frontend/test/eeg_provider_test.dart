import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vr_fast_dashboard/providers/eeg_provider.dart';
import 'package:vr_fast_dashboard/widgets/eeg_panel.dart';

Map<String, dynamic> _payload({
  required int sequence,
  required List<double> fp1,
  required List<double> fp2,
  int samplingRate = 2,
}) {
  return {
    'type': 'eeg_data',
    'sampling_rate': samplingRate,
    'channels': ['Fp1', 'Fp2'],
    'raw_signal': {'Fp1': fp1, 'Fp2': fp2},
    'data_uv': [fp1.last, fp2.last],
    'band_power': <String, dynamic>{},
    'erd': <String, dynamic>{},
    'focus_index': 0,
    'sequence': sequence,
    'sample_start': sequence * fp1.length,
    'sample_count': fp1.length,
  };
}

void main() {
  test('keeps separate five-second rolling buffers per channel', () {
    final provider = EegProvider();

    provider.updateFromJson(
      _payload(
        sequence: 0,
        fp1: [0, 1, 2, 3, 4, 5],
        fp2: [100, 101, 102, 103, 104, 105],
      ),
    );
    provider.updateFromJson(
      _payload(
        sequence: 1,
        fp1: [6, 7, 8, 9, 10, 11],
        fp2: [106, 107, 108, 109, 110, 111],
      ),
    );

    expect(provider.samplesForChannel('Fp1'), [2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
    expect(provider.samplesForChannel('Fp2'), [
      102,
      103,
      104,
      105,
      106,
      107,
      108,
      109,
      110,
      111,
    ]);
    expect(provider.latest?.sequence, 1);
    expect(provider.latest?.sampleCount, 6);
  });

  test('clears samples when the channel configuration changes', () {
    final provider = EegProvider();
    provider.updateFromJson(_payload(sequence: 0, fp1: [1], fp2: [2]));

    provider.updateFromJson({
      'channels': ['O1'],
      'sampling_rate': 250,
      'raw_signal': {
        'O1': [3, 4],
      },
      'data_uv': [4],
      'sample_count': 2,
    });

    expect(provider.samplesForChannel('Fp1'), isEmpty);
    expect(provider.samplesForChannel('O1'), [3, 4]);
  });

  testWidgets('shows independent channel charts without ERD placeholders', (
    tester,
  ) async {
    final provider = EegProvider()
      ..updateFromJson(_payload(sequence: 0, fp1: [1, 2, 3], fp2: [4, 5, 6]));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider.value(
            value: provider,
            child: const SizedBox(width: 320, height: 700, child: EegPanel()),
          ),
        ),
      ),
    );

    expect(find.text('Fp1'), findsOneWidget);
    expect(find.text('Fp2'), findsOneWidget);
    expect(find.text('DANE AKTYWNE'), findsOneWidget);
    expect(find.textContaining('ERD'), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('BRAK ŚWIEŻYCH DANYCH'), findsOneWidget);
  });
}
