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
  final DateTime timestamp;

  EyeTrackingData({
    required this.playerPosition,
    required this.eyesPosition,
    required this.eyesTransform,
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
    );
  }

  /// Convert 3D world position to 2D screen coordinates
  /// Simple heuristic: Map X,Y to screen space assuming a top-down view
  ///
  /// TODO: For production, calibrate with actual game camera parameters:
  ///   - Camera position in world space
  ///   - Camera FOV and projection matrix
  ///   - World-to-screen transformation
  Offset toScreenCoordinate(Size screenSize) {
    // Simple mapping: Normalize world coordinates to screen space
    // Adjust these constants based on your game world size and camera setup
    const double minX = 100.0; // Game world X bounds
    const double maxX = 150.0;
    const double minZ = 80.0; // Game world Z bounds
    const double maxZ = 110.0;

    // Clamp and normalize to 0-1 range
    double normalizedX = ((eyesPosition.x - minX) / (maxX - minX)).clamp(
      0.0,
      1.0,
    );
    double normalizedZ = ((eyesPosition.z - minZ) / (maxZ - minZ)).clamp(
      0.0,
      1.0,
    );

    // Map to screen coordinates (invert Z for screen Y)
    double screenX = normalizedX * screenSize.width;
    double screenY = (1.0 - normalizedZ) * screenSize.height;

    return Offset(screenX, screenY);
  }
}

class EyeTrackingProvider with ChangeNotifier {
  EyeTrackingData? _lastEyeData;
  bool _isEnabled = true;

  EyeTrackingData? get lastEyeData => _lastEyeData;
  bool get isEnabled => _isEnabled;

  void updateEyeData(EyeTrackingData data) {
    _lastEyeData = data;
    notifyListeners();
  }

  void updateFromJson(Map<String, dynamic> json) {
    try {
      _lastEyeData = EyeTrackingData.fromJson(json);
      notifyListeners();
    } catch (e) {
      print('❌ Failed to parse eye tracking data: $e');
    }
  }

  void toggleEyeTracking() {
    _isEnabled = !_isEnabled;
    notifyListeners();
  }

  void setEyeTrackingEnabled(bool enabled) {
    _isEnabled = enabled;
    notifyListeners();
  }

  /// Get both eye gaze positions (for future: implement actual eye separation)
  List<Offset> getGazePoints(Size screenSize) {
    if (_lastEyeData == null) return [];

    // For now, both eyes converge at the same point
    // TODO: Separate left/right eye gaze based on eyes_transform divergence
    final gazePoint = _lastEyeData!.toScreenCoordinate(screenSize);
    return [gazePoint]; // Return as list for future expansion to 2 points
  }
}
