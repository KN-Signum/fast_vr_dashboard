import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

const int kEegDisplaySeconds = 5;
const int kEegSnapshotBufferSize = 30;

const List<String> kEegChannels = ['Fp1', 'Fp2', 'O1', 'O2'];

class EegSnapshot {
  final List<String> channels;
  final List<double> dataUv;
  final int samplingRate;
  final Map<String, List<double>> rawSignal;
  final Map<String, List<double>> bandPower;
  final Map<String, List<double>> erd;
  final double focusIndex;
  final int sequence;
  final int sampleStart;
  final int sampleCount;
  final DateTime timestamp;

  EegSnapshot({
    required this.channels,
    required this.dataUv,
    required this.samplingRate,
    required this.rawSignal,
    required this.bandPower,
    required this.erd,
    required this.focusIndex,
    required this.sequence,
    required this.sampleStart,
    required this.sampleCount,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory EegSnapshot.fromJson(Map<String, dynamic> json) {
    Map<String, List<double>> parseSeries(dynamic raw) {
      if (raw is! Map) return {};
      return raw.map(
        (key, value) => MapEntry(
          key.toString(),
          value is List
              ? value.map((item) => (item as num).toDouble()).toList()
              : <double>[],
        ),
      );
    }

    return EegSnapshot(
      channels: List<String>.from(json['channels'] ?? const []),
      dataUv:
          (json['data_uv'] as List?)
              ?.map((item) => (item as num).toDouble())
              .toList() ??
          const [],
      samplingRate: (json['sampling_rate'] as num?)?.toInt() ?? 250,
      rawSignal: parseSeries(json['raw_signal']),
      bandPower: parseSeries(json['band_power']),
      erd: parseSeries(json['erd']),
      focusIndex: (json['focus_index'] as num?)?.toDouble() ?? 0.0,
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      sampleStart: (json['sample_start'] as num?)?.toInt() ?? 0,
      sampleCount: (json['sample_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class EegProvider with ChangeNotifier {
  final Queue<EegSnapshot> _snapshots = Queue();
  final Map<String, List<double>> _channelSamples = {};
  Timer? _freshnessTimer;
  bool _hasFreshData = false;

  List<EegSnapshot> get snapshots => _snapshots.toList(growable: false);

  EegSnapshot? get latest => _snapshots.isEmpty ? null : _snapshots.last;

  bool get hasFreshData => _hasFreshData;

  List<double> samplesForChannel(String channel) =>
      List.unmodifiable(_channelSamples[channel] ?? const <double>[]);

  void updateFromJson(Map<String, dynamic> json) {
    try {
      final snapshot = EegSnapshot.fromJson(json);
      if (!_sameChannels(snapshot.channels, latest?.channels)) {
        _channelSamples.clear();
      }

      final sampleLimit = snapshot.samplingRate * kEegDisplaySeconds;
      for (final channel in snapshot.channels) {
        final incoming = snapshot.rawSignal[channel];
        if (incoming == null || incoming.isEmpty) continue;

        final samples = _channelSamples.putIfAbsent(channel, () => []);
        samples.addAll(incoming);
        if (samples.length > sampleLimit) {
          samples.removeRange(0, samples.length - sampleLimit);
        }
      }

      _snapshots.addLast(snapshot);
      if (_snapshots.length > kEegSnapshotBufferSize) {
        _snapshots.removeFirst();
      }

      _freshnessTimer?.cancel();
      _hasFreshData = true;
      _freshnessTimer = Timer(const Duration(seconds: 3), () {
        _hasFreshData = false;
        notifyListeners();
      });

      debugPrint(
        'EEG: sekwencja=${snapshot.sequence}, '
        'próbki=${snapshot.sampleCount}, kanały=${snapshot.channels.length}',
      );
      notifyListeners();
    } catch (error) {
      debugPrint('Nie udało się przetworzyć danych EEG: $error');
    }
  }

  List<String> getChannels() => latest?.channels ?? kEegChannels;

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    super.dispose();
  }

  bool _sameChannels(List<String> current, List<String>? previous) {
    if (previous == null || current.length != previous.length) return false;
    for (var index = 0; index < current.length; index++) {
      if (current[index] != previous[index]) return false;
    }
    return true;
  }
}
