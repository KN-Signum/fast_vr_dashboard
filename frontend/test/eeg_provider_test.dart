import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vr_fast_dashboard/providers/eeg_provider.dart';
import 'package:vr_fast_dashboard/widgets/eeg_panel.dart';

Map<String, dynamic> _payload({
  required int sequence,
  required List<String> channels,
  required Map<String, List<double>> rawSignal,
  Map<String, List<double>> erd = const {},
  String? erdStatus,
  int? erdBaselineSeconds,
  int? erdBaselineTargetSeconds,
  int samplingRate = 2,
  int? timestampMs,
}) {
  final sampleCount = rawSignal.values.first.length;
  return {
    'type': 'eeg_data',
    'sampling_rate': samplingRate,
    'channels': channels,
    'raw_signal': rawSignal,
    'data_uv': channels.map((channel) => rawSignal[channel]!.last).toList(),
    'band_power': <String, dynamic>{},
    'erd': erd,
    'erd_conventional': <String, dynamic>{},
    if (erdStatus != null) 'erd_status': erdStatus,
    if (erdBaselineSeconds != null) 'erd_baseline_seconds': erdBaselineSeconds,
    if (erdBaselineTargetSeconds != null)
      'erd_baseline_target_seconds': erdBaselineTargetSeconds,
    'focus_index': 0,
    'sequence': sequence,
    'sample_start': sequence * sampleCount,
    'sample_count': sampleCount,
    if (timestampMs != null) 'timestamp_ms': timestampMs,
  };
}

void main() {
  test('keeps separate 60-second rolling buffers per channel', () {
    final provider = EegProvider();

    provider.updateFromJson(
      _payload(
        sequence: 0,
        channels: const ['Fp1', 'Fp2'],
        rawSignal: {
          'Fp1': List.generate(80, (index) => index.toDouble()),
          'Fp2': List.generate(80, (index) => 100 + index.toDouble()),
        },
      ),
    );
    provider.updateFromJson(
      _payload(
        sequence: 1,
        channels: const ['Fp1', 'Fp2'],
        rawSignal: {
          'Fp1': List.generate(80, (index) => 80 + index.toDouble()),
          'Fp2': List.generate(80, (index) => 180 + index.toDouble()),
        },
      ),
    );

    expect(provider.samplesForChannel('Fp1'), hasLength(120));
    expect(provider.samplesForChannel('Fp1').first, 40);
    expect(provider.samplesForChannel('Fp1').last, 159);
    expect(provider.samplesForChannel('Fp2').first, 140);
  });

  test(
    'enables at most eight channels and toggles display without data loss',
    () {
      final provider = EegProvider();
      final channels = List.generate(9, (index) => 'C$index');
      final signals = {
        for (final channel in channels) channel: <double>[1, 2],
      };

      provider.updateFromJson(
        _payload(sequence: 0, channels: channels, rawSignal: signals),
      );

      expect(provider.getChannels(), channels.take(8));
      expect(provider.enabledChannels, channels.take(8).toSet());
      provider.toggleChannel('C0');
      expect(provider.isChannelEnabled('C0'), isFalse);
      expect(provider.samplesForChannel('C0'), [1, 2]);
    },
  );

  test(
    'maps alpha ERD to channels and removes history older than 60 seconds',
    () {
      final provider = EegProvider();
      const channels = ['Fp1', 'Fp2'];
      const signal = {
        'Fp1': <double>[1],
        'Fp2': <double>[2],
      };

      provider.updateFromJson(
        _payload(
          sequence: 0,
          channels: channels,
          rawSignal: signal,
          erd: const {
            'alpha': [10, 20],
          },
          timestampMs: 1000,
        ),
      );
      provider.updateFromJson(
        _payload(
          sequence: 1,
          channels: channels,
          rawSignal: signal,
          erd: const {
            'alpha': [30, 40],
          },
          timestampMs: 62000,
        ),
      );

      expect(provider.alphaErdHistory, hasLength(1));
      expect(provider.alphaErdHistory.single.values, {'Fp1': 30, 'Fp2': 40});
    },
  );

  test('channel configuration change resets selection and ERD history', () {
    final provider = EegProvider();
    provider.updateFromJson(
      _payload(
        sequence: 0,
        channels: const ['Fp1'],
        rawSignal: const {
          'Fp1': [1],
        },
        erd: const {
          'alpha': [10],
        },
      ),
    );
    provider.toggleChannel('Fp1');

    provider.updateFromJson(
      _payload(
        sequence: 1,
        channels: const ['O1'],
        rawSignal: const {
          'O1': [2],
        },
      ),
    );

    expect(provider.samplesForChannel('Fp1'), isEmpty);
    expect(provider.isChannelEnabled('O1'), isTrue);
    expect(provider.alphaErdHistory, isEmpty);
  });

  testWidgets('shows channel controls and ERD unavailable state', (
    tester,
  ) async {
    final provider = EegProvider()
      ..updateFromJson(
        _payload(
          sequence: 0,
          channels: const ['Fp1', 'Fp2'],
          rawSignal: const {
            'Fp1': [1, 2, 3],
            'Fp2': [4, 5, 6],
          },
        ),
      );

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

    expect(find.text('Znormalizowana zmiana alfa'), findsOneWidget);
    expect(find.text('Zmiana alfa nie jest dostępna'), findsOneWidget);
    expect(find.byType(FilterChip), findsNWidgets(2));
    expect(find.text('Fp1'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(FilterChip, 'Fp1'));
    await tester.pump();
    expect(find.text('Fp1'), findsOneWidget);
    expect(provider.samplesForChannel('Fp1'), [1, 2, 3]);

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('shows eight channel controls and normalized alpha change', (
    tester,
  ) async {
    final channels = List.generate(8, (index) => 'C$index');
    final provider = EegProvider()
      ..updateFromJson(
        _payload(
          sequence: 0,
          channels: channels,
          rawSignal: {
            for (final channel in channels) channel: <double>[1, 2, 3],
          },
          erd: {'alpha': List.generate(8, (index) => index.toDouble())},
        ),
      );

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

    expect(find.byType(FilterChip), findsNWidgets(8));
    expect(find.text('Znormalizowana zmiana alfa'), findsOneWidget);
    expect(find.text('Zmiana alfa nie jest dostępna'), findsNothing);

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('shows real ERD baseline progress', (tester) async {
    final provider = EegProvider()
      ..updateFromJson(
        _payload(
          sequence: 0,
          channels: const ['C3'],
          rawSignal: const {
            'C3': [1, 2, 3],
          },
          erdStatus: 'collecting',
          erdBaselineSeconds: 12,
          erdBaselineTargetSeconds: 30,
        ),
      );

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

    expect(find.text('Zbieranie linii bazowej alfa: 12/30 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  test('filters preview without changing raw samples and detects clipping', () {
    final provider = EegProvider()
      ..updateFromJson(
        _payload(
          sequence: 0,
          channels: const ['F4'],
          rawSignal: const {
            'F4': [562500, 562500, 562490, 562480],
          },
          samplingRate: 250,
        ),
      );

    expect(provider.samplesForChannel('F4'), [562500, 562500, 562490, 562480]);
    expect(
      provider.displaySamplesForChannel('F4'),
      isNot(equals([562500, 562500, 562490, 562480])),
    );
    expect(provider.qualityForChannel('F4').clipping, isTrue);
  });
}
