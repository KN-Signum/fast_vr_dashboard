import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vr_fast_dashboard/providers/eye_tracking_provider.dart';
import 'package:vr_fast_dashboard/widgets/eye_tracking_overlay.dart';

void main() {
  test('eye tracking updates notify the custom painter directly', () {
    final provider = EyeTrackingProvider();
    final painter = EyeTrackingOverlay(
      provider: provider,
      canvasSize: const Size(1280, 720),
    );
    var repaintCount = 0;

    painter.addListener(() => repaintCount++);
    provider.updateFromJson(_eyeTrackingPayload());

    expect(repaintCount, 1);
    expect(provider.lastEyeData, isNotNull);
    expect(
      provider.lastEyeData!.toScreenCoordinate(const Size(1280, 720)),
      const Offset(320, 180),
    );
    provider.dispose();
  });

  test('painter identity only changes for a new provider or canvas size', () {
    final provider = EyeTrackingProvider();
    final original = EyeTrackingOverlay(
      provider: provider,
      canvasSize: const Size(1280, 720),
    );

    expect(
      EyeTrackingOverlay(
        provider: provider,
        canvasSize: const Size(1280, 720),
      ).shouldRepaint(original),
      isFalse,
    );
    expect(
      EyeTrackingOverlay(
        provider: provider,
        canvasSize: const Size(640, 360),
      ).shouldRepaint(original),
      isTrue,
    );
    expect(
      EyeTrackingOverlay(
        provider: EyeTrackingProvider(),
        canvasSize: const Size(1280, 720),
      ).shouldRepaint(original),
      isTrue,
    );
  });

  testWidgets('receiving status expires when ET samples stop', (tester) async {
    final provider = EyeTrackingProvider();
    provider.updateFromJson(_eyeTrackingPayload());

    expect(provider.isReceiving, isTrue);

    await tester.pump(const Duration(seconds: 4));

    expect(provider.isReceiving, isFalse);
    provider.dispose();
  });

  test('invalid screen coordinates do not fall back to preview edges', () {
    final provider = EyeTrackingProvider();
    provider.updateFromJson({
      ..._eyeTrackingPayload(),
      'gaze_screen_x': -1,
      'gaze_screen_y': -1,
    });

    expect(provider.getGazePoints(const Size(1280, 720)), isEmpty);
    provider.dispose();
  });
}

Map<String, dynamic> _eyeTrackingPayload() {
  return {
    'type': 'eye_tracking',
    'player_position': {'x': 0.0, 'y': 1.6, 'z': 0.0},
    'eyes_position': {'x': 0.0, 'y': 1.6, 'z': 5.0},
    'eyes_transform': {
      'x_axis': {'x': 1.0, 'y': 0.0, 'z': 0.0},
      'y_axis': {'x': 0.0, 'y': 1.0, 'z': 0.0},
      'z_axis': {'x': 0.0, 'y': 0.0, 'z': 1.0},
      'origin': {'x': 0.0, 'y': 1.6, 'z': 0.0},
    },
    'gaze_screen_x': 0.25,
    'gaze_screen_y': 0.75,
  };
}
