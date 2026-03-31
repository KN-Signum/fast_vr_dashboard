import 'dart:collection';
import 'package:flutter/foundation.dart';

const int kEegBufferSeconds = 30;
const int kEegHz = 10; // backend sends at 10 Hz
const int kEegBufferSize = kEegBufferSeconds * kEegHz; // 300 points

// Channel names matching backend CHANNELS list
const List<String> kEegChannels = [
  'Fp1', 'Fp2', 'F3', 'F4', 'C3', 'C4', 'P3', 'P4'
];

/// Holds a single EEG snapshot received from the backend.
class EegSnapshot {
  final Map<String, List<double>> bandPower; // band → per-channel values
  final Map<String, List<double>> erd;       // band → per-channel ERD%
  final double focusIndex;
  final DateTime timestamp;

  EegSnapshot({
    required this.bandPower,
    required this.erd,
    required this.focusIndex,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory EegSnapshot.fromJson(Map<String, dynamic> json) {
    Map<String, List<double>> parseBands(dynamic raw) {
      final map = raw as Map<String, dynamic>;
      return map.map(
        (k, v) => MapEntry(k, (v as List).map((e) => (e as num).toDouble()).toList()),
      );
    }

    return EegSnapshot(
      bandPower: parseBands(json['band_power']),
      erd:       parseBands(json['erd']),
      focusIndex: (json['focus_index'] as num).toDouble(),
    );
  }
}

class EegProvider with ChangeNotifier {
  // Rolling buffer of snapshots (fixed max length = kEegBufferSize)
  final Queue<EegSnapshot> _buffer = Queue();

  bool _isEnabled = true;

  bool get isEnabled => _isEnabled;

  /// Unmodifiable view of the rolling buffer.
  List<EegSnapshot> get snapshots => _buffer.toList(growable: false);

  /// Most recent snapshot, or null if no data yet.
  EegSnapshot? get latest => _buffer.isEmpty ? null : _buffer.last;

  void updateFromJson(Map<String, dynamic> json) {
    try {
      final snapshot = EegSnapshot.fromJson(json);
      _buffer.addLast(snapshot);
      if (_buffer.length > kEegBufferSize) _buffer.removeFirst();
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to parse EEG data: $e');
    }
  }

  /// Returns a list of [count] averaged-across-channels values for [band]
  /// from the rolling buffer — used to populate a line chart.
  List<double> bandTimeSeries(String band, {int? count}) {
    final snaps = _buffer.toList();
    final n = count ?? snaps.length;
    final slice = snaps.length > n ? snaps.sublist(snaps.length - n) : snaps;
    return slice.map((s) {
      final vals = s.bandPower[band];
      if (vals == null || vals.isEmpty) return 0.0;
      return vals.reduce((a, b) => a + b) / vals.length;
    }).toList();
  }

  /// Returns per-channel ERD% values from the most recent snapshot for [band].
  List<double> latestErd(String band) {
    final snap = latest;
    if (snap == null) return List.filled(kEegChannels.length, 0.0);
    return snap.erd[band] ?? List.filled(kEegChannels.length, 0.0);
  }

  void toggleEnabled() {
    _isEnabled = !_isEnabled;
    notifyListeners();
  }
}
