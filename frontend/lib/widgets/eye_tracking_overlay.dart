import 'package:flutter/material.dart';
import '../providers/eye_tracking_provider.dart';

class EyeTrackingOverlay extends CustomPainter {
  final EyeTrackingProvider provider;
  final Size canvasSize;

  EyeTrackingOverlay({required this.provider, required this.canvasSize})
    : super(repaint: provider);

  @override
  void paint(Canvas canvas, Size size) {
    if (!provider.isEnabled || provider.lastEyeData == null) {
      return;
    }

    final gazePoints = provider.getGazePoints(canvasSize);

    // Paint settings for gaze dot
    final gazePaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    // Paint for gaze indicator circle (outline)
    final gazeBorderPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    const double gazeRadius = 8.0;
    const double indicatorRadius = 16.0;

    // Draw each gaze point (currently just one, expandable for two eyes)
    for (final gazePoint in gazePoints) {
      // Draw outer indicator circle (for visibility)
      canvas.drawCircle(gazePoint, indicatorRadius, gazeBorderPaint);

      // Draw center gaze dot
      canvas.drawCircle(gazePoint, gazeRadius, gazePaint);

      // Optional: Draw crosshair
      _drawCrosshair(canvas, gazePoint, gazeRadius + 4);
    }
  }

  void _drawCrosshair(Canvas canvas, Offset center, double size) {
    final crosshairPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.5)
      ..strokeWidth = 1.0;

    // Horizontal line
    canvas.drawLine(
      Offset(center.dx - size, center.dy),
      Offset(center.dx + size, center.dy),
      crosshairPaint,
    );

    // Vertical line
    canvas.drawLine(
      Offset(center.dx, center.dy - size),
      Offset(center.dx, center.dy + size),
      crosshairPaint,
    );
  }

  @override
  bool shouldRepaint(EyeTrackingOverlay oldDelegate) {
    return oldDelegate.provider != provider ||
        oldDelegate.canvasSize != canvasSize;
  }
}

/// Widget to display eye tracking visualization over the game preview
class EyeTrackingVisualizationLayer extends StatelessWidget {
  final EyeTrackingProvider eyeTrackingProvider;
  final Size previewSize;

  const EyeTrackingVisualizationLayer({
    super.key,
    required this.eyeTrackingProvider,
    required this.previewSize,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: EyeTrackingOverlay(
        provider: eyeTrackingProvider,
        canvasSize: previewSize,
      ),
      size: previewSize,
    );
  }
}
