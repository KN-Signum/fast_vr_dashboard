import 'dart:async';

import 'package:flutter/material.dart';

// Data models for Eye Tracking
class Vector3 {
  final double x;
  final double y;
  final double z;

  Vector3({required this.x, required this.y, required this.z});

  factory Vector3.fromJson(Map<String, dynamic> json) {
    return Vector3(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: (json['z'] as num).toDouble(),
    );
  }
}

class EyeTransform {
  final Vector3 xAxis; // Right vector
  final Vector3 yAxis; // Up vector
  final Vector3 zAxis; // Forward vector (gaze direction)
  final Vector3 origin; // Eye position in world space

  EyeTransform({
    required this.xAxis,
    required this.yAxis,
    required this.zAxis,
    required this.origin,
  });

  factory EyeTransform.fromJson(Map<String, dynamic> json) {
    return EyeTransform(
      xAxis: Vector3.fromJson(json['x_axis'] as Map<String, dynamic>),
      yAxis: Vector3.fromJson(json['y_axis'] as Map<String, dynamic>),
      zAxis: Vector3.fromJson(json['z_axis'] as Map<String, dynamic>),
      origin: Vector3.fromJson(json['origin'] as Map<String, dynamic>),
    );
  }
}

class EyeTrackingData {
  final Vector3 playerPosition;
  final Vector3 eyesPosition;
  final EyeTransform eyesTransform;
  final double? gazeScreenX;
  final double? gazeScreenY;
  final DateTime timestamp;

  EyeTrackingData({
    required this.playerPosition,
    required this.eyesPosition,
    required this.eyesTransform,
    this.gazeScreenX,
    this.gazeScreenY,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory EyeTrackingData.fromJson(Map<String, dynamic> json) {
    return EyeTrackingData(
      playerPosition: Vector3.fromJson(
        json['player_position'] as Map<String, dynamic>,
      ),
      eyesPosition: Vector3.fromJson(
        json['eyes_position'] as Map<String, dynamic>,
      ),
      eyesTransform: EyeTransform.fromJson(
        json['eyes_transform'] as Map<String, dynamic>,
      ),
      gazeScreenX: _optionalScreenCoord(json['gaze_screen_x']),
      gazeScreenY: _optionalScreenCoord(json['gaze_screen_y']),
    );
  }

  static double? _optionalScreenCoord(dynamic value) {
    if (value is! num) return null;
    final coord = value.toDouble();
    if (!coord.isFinite || coord < 0 || coord > 1) return null;
    return coord;
  }

  /// Map gaze to preview coordinates.
  /// Returns null when the headset could not project gaze into the streamed view.
  Offset? toScreenCoordinate(Size screenSize) {
    if (gazeScreenX == null || gazeScreenY == null) return null;
    return Offset(
      gazeScreenX! * screenSize.width,
      (1.0 - gazeScreenY!) * screenSize.height,
    );
  }
}

class EyeTrackingProvider with ChangeNotifier {
  EyeTrackingData? _lastEyeData;
  bool _isEnabled = true;
  bool _isReceiving = false;
  Timer? _staleTimer;

  EyeTrackingData? get lastEyeData => _lastEyeData;
  bool get isEnabled => _isEnabled;
  bool get isReceiving => _isReceiving;

  void updateFromJson(Map<String, dynamic> json) {
    try {
      _lastEyeData = EyeTrackingData.fromJson(json);
      _isReceiving = true;
      _staleTimer?.cancel();
      _staleTimer = Timer(const Duration(seconds: 3), () {
        _isReceiving = false;
        notifyListeners();
      });
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to parse eye tracking data: $e');
    }
  }

  void toggleEyeTracking() {
    _isEnabled = !_isEnabled;
    notifyListeners();
  }

  List<Offset> getGazePoints(Size screenSize) {
    if (_lastEyeData == null) return [];

    final gazePoint = _lastEyeData!.toScreenCoordinate(screenSize);
    if (gazePoint == null) return [];
    return [gazePoint];
  }

  @override
  void dispose() {
    _staleTimer?.cancel();
    super.dispose();
  }
}
