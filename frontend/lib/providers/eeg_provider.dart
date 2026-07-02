import 'dart:collection';
import 'package:flutter/foundation.dart';

const int kEegBufferSeconds = 30;
const int kEegHz = 10; // backend sends at 10 Hz
const int kEegBufferSize = kEegBufferSeconds * kEegHz; // 300 points

// Default channel names (may be overridden by payload)
const List<String> kEegChannels = [
  'F3',
  'F4',
  'C3',
  'C4',
  'P3',
  'P4',
  'O1',
  'O2',
];

/// Holds a single EEG snapshot received from the backend.
class EegSnapshot {
  final List<String> channels; // Channel names from payload
  final List<double> dataUv; // Raw microvolts data
  final int samplingRate; // Sampling rate in Hz
  final Map<String, List<double>> rawSignal; // Raw waveform per channel
  final Map<String, List<double>> bandPower; // band → per-channel values
  final Map<String, List<double>> erd; // band → per-channel ERD% (may be empty)
  final double focusIndex;
  final DateTime timestamp;

  EegSnapshot({
    required this.channels,
    required this.dataUv,
    required this.samplingRate,
    required this.rawSignal,
    required this.bandPower,
    required this.erd,
    required this.focusIndex,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory EegSnapshot.fromJson(Map<String, dynamic> json) {
    Map<String, List<double>> parseBands(dynamic raw) {
      if (raw == null) return {};
      final map = raw as Map<String, dynamic>;
      return map.map(
        (k, v) =>
            MapEntry(k, (v as List).map((e) => (e as num).toDouble()).toList()),
      );
    }

    final channels = List<String>.from(json['channels'] ?? []);
    final dataUv =
        (json['data_uv'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [];
    final samplingRate = (json['sampling_rate'] as num?)?.toInt() ?? 250;

    return EegSnapshot(
      channels: channels,
      dataUv: dataUv,
      samplingRate: samplingRate,
      rawSignal: parseBands(json['raw_signal']),
      bandPower: parseBands(json['band_power']),
      erd: parseBands(json['erd']), // May be empty if not in payload
      focusIndex: (json['focus_index'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class EegProvider with ChangeNotifier {
  // Rolling buffer of snapshots (fixed max length = kEegBufferSize)
  final Queue<EegSnapshot> _buffer = Queue();

  /// Unmodifiable view of the rolling buffer.
  List<EegSnapshot> get snapshots => _buffer.toList(growable: false);

  /// Most recent snapshot, or null if no data yet.
  EegSnapshot? get latest => _buffer.isEmpty ? null : _buffer.last;

  void updateFromJson(Map<String, dynamic> json) {
    try {
      debugPrint('🧠 EEG raw payload keys: ${json.keys.toList()}');
      final snapshot = EegSnapshot.fromJson(json);
      _buffer.addLast(snapshot);
      if (_buffer.length > kEegBufferSize) _buffer.removeFirst();

      // Debug logging
      debugPrint(
        '✅ EEG snapshot: channels=${snapshot.channels.length} '
        'samplingRate=${snapshot.samplingRate} '
        'focus=${snapshot.focusIndex.toStringAsFixed(3)} '
        'alpha=${snapshot.bandPower['alpha']?.length ?? 0} '
        'beta=${snapshot.bandPower['beta']?.length ?? 0}',
      );

      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to parse EEG data: $e');
      debugPrint('Raw JSON: $json');
    }
  }

  /// Returns the list of channel names from the most recent snapshot.
  List<String> getChannels() {
    return latest?.channels ?? kEegChannels;
  }
}
