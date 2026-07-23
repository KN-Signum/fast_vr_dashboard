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
    if (coord < 0) return null;
    return coord;
  }

  /// Map gaze to preview coordinates.
  /// Prefers normalized spectator-camera UVs from the headset when present.
  Offset toScreenCoordinate(Size screenSize) {
    if (gazeScreenX != null && gazeScreenY != null) {
      return Offset(
        gazeScreenX!.clamp(0.0, 1.0) * screenSize.width,
        (1.0 - gazeScreenY!.clamp(0.0, 1.0)) * screenSize.height,
      );
    }

    // Fallback: project gaze hit point relative to the player on the XZ plane.
    const worldSpan = 24.0;
    final dx = eyesPosition.x - playerPosition.x;
    final dz = eyesPosition.z - playerPosition.z;

    final normalizedX = (0.5 + (dx / worldSpan)).clamp(0.0, 1.0);
    final normalizedY = (0.5 - (dz / worldSpan)).clamp(0.0, 1.0);

    return Offset(
      normalizedX * screenSize.width,
      normalizedY * screenSize.height,
    );
  }
}

class EyeTrackingProvider with ChangeNotifier {
  EyeTrackingData? _lastEyeData;
  bool _isEnabled = true;

  EyeTrackingData? get lastEyeData => _lastEyeData;
  bool get isEnabled => _isEnabled;
  bool get isReceiving {
    final data = _lastEyeData;
    if (data == null) return false;
    return DateTime.now().difference(data.timestamp) <=
        const Duration(seconds: 3);
  }

  void updateFromJson(Map<String, dynamic> json) {
    try {
      _lastEyeData = EyeTrackingData.fromJson(json);
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
    return [gazePoint];
  }
}
