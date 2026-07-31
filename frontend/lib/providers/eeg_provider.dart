import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

const int kEegDisplaySeconds = 30;
const int kErdDisplaySeconds = 30;
const int kMaxVisibleEegChannels = 8;
const int kEegSnapshotBufferSize = 30;

const List<String> kEegChannels = ['Fp1', 'Fp2', 'O1', 'O2'];

class EegErdPoint {
  final DateTime timestamp;
  final Map<String, double> values;

  const EegErdPoint({required this.timestamp, required this.values});
}

class EegChannelQuality {
  final bool clipping;
  final bool flat;
  final bool highAmplitude;

  const EegChannelQuality({
    this.clipping = false,
    this.flat = false,
    this.highAmplitude = false,
  });

  bool get hasWarning => clipping || flat || highAmplitude;
}

class _PreviewFilter {
  final double _highPassAlpha;
  final double _lowPassAlpha;
  bool _initialized = false;
  double _previousInput = 0;
  double _highPass = 0;
  double _lowPass = 0;

  _PreviewFilter(int samplingRate)
    : _highPassAlpha = _highPassCoefficient(samplingRate, 1),
      _lowPassAlpha = _lowPassCoefficient(samplingRate, 40);

  double process(double input) {
    if (!_initialized) {
      _initialized = true;
      _previousInput = input;
      return 0;
    }

    _highPass = _highPassAlpha * (_highPass + input - _previousInput);
    _previousInput = input;
    _lowPass += _lowPassAlpha * (_highPass - _lowPass);
    return _lowPass;
  }

  static double _highPassCoefficient(int samplingRate, double cutoff) {
    final dt = 1 / samplingRate;
    final rc = 1 / (2 * math.pi * cutoff);
    return rc / (rc + dt);
  }

  static double _lowPassCoefficient(int samplingRate, double cutoff) {
    final dt = 1 / samplingRate;
    final rc = 1 / (2 * math.pi * cutoff);
    return dt / (rc + dt);
  }
}

class EegSnapshot {
  final List<String> channels;
  final List<double> dataUv;
  final int samplingRate;
  final Map<String, List<double>> rawSignal;
  final Map<String, List<double>> bandPower;
  final Map<String, List<double>> erd;
  final Map<String, List<double>> conventionalErd;
  final String erdStatus;
  final int erdBaselineSeconds;
  final int erdBaselineTargetSeconds;
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
    required this.conventionalErd,
    required this.erdStatus,
    required this.erdBaselineSeconds,
    required this.erdBaselineTargetSeconds,
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

    final timestampMs = (json['timestamp_ms'] as num?)?.toInt();

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
      conventionalErd: parseSeries(json['erd_conventional']),
      erdStatus: json['erd_status'] as String? ?? 'unavailable',
      erdBaselineSeconds: (json['erd_baseline_seconds'] as num?)?.toInt() ?? 0,
      erdBaselineTargetSeconds:
          (json['erd_baseline_target_seconds'] as num?)?.toInt() ?? 30,
      focusIndex: (json['focus_index'] as num?)?.toDouble() ?? 0.0,
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      sampleStart: (json['sample_start'] as num?)?.toInt() ?? 0,
      sampleCount: (json['sample_count'] as num?)?.toInt() ?? 0,
      timestamp: timestampMs == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );
  }
}

class EegProvider with ChangeNotifier {
  final Queue<EegSnapshot> _snapshots = Queue();
  final Map<String, List<double>> _channelSamples = {};
  final Map<String, List<double>> _filteredChannelSamples = {};
  final Map<String, _PreviewFilter> _previewFilters = {};
  final Map<String, EegChannelQuality> _channelQuality = {};
  final Set<String> _enabledChannels = {};
  final List<EegErdPoint> _alphaErdHistory = [];
  Timer? _freshnessTimer;
  bool _hasFreshData = false;

  List<EegSnapshot> get snapshots => _snapshots.toList(growable: false);

  EegSnapshot? get latest => _snapshots.isEmpty ? null : _snapshots.last;

  bool get hasFreshData => _hasFreshData;

  Set<String> get enabledChannels => Set.unmodifiable(_enabledChannels);

  List<EegErdPoint> get alphaErdHistory => List.unmodifiable(_alphaErdHistory);

  List<double> samplesForChannel(String channel) =>
      List.unmodifiable(_channelSamples[channel] ?? const <double>[]);

  List<double> displaySamplesForChannel(String channel) =>
      List.unmodifiable(_filteredChannelSamples[channel] ?? const <double>[]);

  EegChannelQuality qualityForChannel(String channel) =>
      _channelQuality[channel] ?? const EegChannelQuality();

  bool isChannelEnabled(String channel) => _enabledChannels.contains(channel);

  void toggleChannel(String channel) {
    if (_enabledChannels.contains(channel)) {
      _enabledChannels.remove(channel);
    } else {
      _enabledChannels.add(channel);
    }
    notifyListeners();
  }

  void updateFromJson(Map<String, dynamic> json) {
    try {
      final snapshot = EegSnapshot.fromJson(json);
      if (!_sameChannels(snapshot.channels, latest?.channels)) {
        _channelSamples.clear();
        _filteredChannelSamples.clear();
        _previewFilters.clear();
        _channelQuality.clear();
        _alphaErdHistory.clear();
        _enabledChannels
          ..clear()
          ..addAll(snapshot.channels.take(kMaxVisibleEegChannels));
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

        final filter = _previewFilters.putIfAbsent(
          channel,
          () => _PreviewFilter(snapshot.samplingRate),
        );
        final filteredIncoming = incoming.map(filter.process).toList();
        final filtered = _filteredChannelSamples.putIfAbsent(channel, () => []);
        filtered.addAll(filteredIncoming);
        if (filtered.length > sampleLimit) {
          filtered.removeRange(0, filtered.length - sampleLimit);
        }
        _channelQuality[channel] = _quality(incoming, filteredIncoming);
      }

      final alphaValues = snapshot.erd['alpha'];
      if (alphaValues != null) {
        final values = <String, double>{};
        final channelCount = snapshot.channels.length;
        final valueCount = alphaValues.length;
        final count = [
          channelCount,
          valueCount,
          kMaxVisibleEegChannels,
        ].reduce((left, right) => left < right ? left : right);

        for (var index = 0; index < count; index++) {
          values[snapshot.channels[index]] = alphaValues[index];
        }

        if (values.isNotEmpty) {
          final now = snapshot.timestamp;
          _alphaErdHistory.add(EegErdPoint(timestamp: now, values: values));
          final cutoff = now.subtract(
            const Duration(seconds: kErdDisplaySeconds),
          );
          _alphaErdHistory.removeWhere(
            (point) => point.timestamp.isBefore(cutoff),
          );
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

  List<String> getChannels() => (latest?.channels ?? kEegChannels)
      .take(kMaxVisibleEegChannels)
      .toList(growable: false);

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

  EegChannelQuality _quality(List<double> raw, List<double> filtered) {
    final rawMin = raw.reduce(math.min);
    final rawMax = raw.reduce(math.max);
    final filteredPeak = filtered.fold<double>(
      0,
      (peak, value) => math.max(peak, value.abs()),
    );
    return EegChannelQuality(
      clipping: raw.any((value) => value.abs() >= 562499),
      flat: rawMax - rawMin < 0.5,
      highAmplitude: filteredPeak > 5000,
    );
  }
}
