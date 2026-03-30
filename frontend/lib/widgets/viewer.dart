import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/web_socket_provider.dart';
import '../providers/device_provider.dart';
import '../providers/eye_tracking_provider.dart';
import 'eye_tracking_overlay.dart';
import 'dart:typed_data';

class Viewer extends StatelessWidget {
  final bool isDrawerOpen;
  final VoidCallback onToggleDrawer;

  const Viewer({
    super.key,
    required this.isDrawerOpen,
    required this.onToggleDrawer,
  });

  @override
  Widget build(BuildContext context) {
    // Pobieramy dane o urządzeniu (rzadkie zmiany)
    final deviceProvider = context.watch<DeviceProvider>();

    return Expanded(
      child: Stack(
        children: [
          // 1. OBSZAR STREAMINGU (Tylko to odświeża się 20+ razy na sekundę)
          Container(
            color: const Color.fromARGB(255, 255, 255, 255),
            child: Center(
              child: Selector<WebSocketProvider, Uint8List?>(
                // Selector sprawia, że ten fragment kodu reaguje TYLKO na zmianę lastFrame
                selector: (_, provider) => provider.lastFrame,
                builder: (context, frame, _) {
                  if (frame == null) {
                    return _buildPlaceholder();
                  }

                  // Build the preview with ET overlay
                  return _buildPreviewWithEyeTracking(context, frame);
                },
              ),
            ),
          ),

          // 2. INTERFEJS NAKŁADKI (Odświeża się rzadko)
          if (!isDrawerOpen)
            Positioned(
              top: 16,
              left: 16,
              child: _buildFloatingMenuButton(context, deviceProvider),
            ),

          // 3. EYE TRACKING TOGGLE (Top-right corner)
          Positioned(
            top: 16,
            right: 16,
            child: _buildEyeTrackingToggle(context),
          ),
        ],
      ),
    );
  }

  /// Build game preview with eye tracking overlay
  Widget _buildPreviewWithEyeTracking(BuildContext context, Uint8List frame) {
    final eyeTrackingProvider = context.watch<EyeTrackingProvider>();

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        children: [
          // Game preview image
          Image.memory(
            frame,
            gaplessPlayback: true, // Kluczowe: zapobiega mruganiu
            filterQuality: FilterQuality.low, // Wyższa wydajność w przeglądarce
            fit: BoxFit.contain,
          ),

          // Eye tracking overlay
          LayoutBuilder(
            builder: (context, constraints) {
              // Calculate actual preview size considering fit: contain
              final previewWidth = constraints.maxWidth;
              final previewHeight = constraints.maxHeight;

              return EyeTrackingVisualizationLayer(
                eyeTrackingProvider: eyeTrackingProvider,
                previewSize: Size(previewWidth, previewHeight),
              );
            },
          ),
        ],
      ),
    );
  }

  // Widget zastępczy, gdy nie ma obrazu
  Widget _buildPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(
          Icons.videocam_off,
          size: 64,
          color: Color.fromARGB(137, 144, 143, 143),
        ),
        SizedBox(height: 16),
        Text(
          'Czekam na pierwszą klatkę…',
          style: TextStyle(
            color: Color.fromARGB(137, 144, 143, 143),
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  // Eye Tracking Toggle Button
  Widget _buildEyeTrackingToggle(BuildContext context) {
    final eyeTrackingProvider = context.watch<EyeTrackingProvider>();

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          eyeTrackingProvider.toggleEyeTracking();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: eyeTrackingProvider.isEnabled
                ? Colors.red.withValues(alpha: 0.2)
                : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: eyeTrackingProvider.isEnabled ? Colors.red : Colors.grey,
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.remove_red_eye,
                size: 18,
                color: eyeTrackingProvider.isEnabled ? Colors.red : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                eyeTrackingProvider.isEnabled ? 'ET: ON' : 'ET: OFF',
                style: TextStyle(
                  fontSize: 12,
                  color: eyeTrackingProvider.isEnabled
                      ? Colors.red
                      : Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Przycisk menu z informacją o połączeniu
  Widget _buildFloatingMenuButton(
    BuildContext context,
    DeviceProvider deviceProvider,
  ) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onToggleDrawer,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu, size: 20, color: Colors.grey.shade700),
              // Selector sprawia, że ikona połączenia zmienia się tylko gdy zmienia się stan kanału
              Selector<WebSocketProvider, bool>(
                selector: (_, provider) => provider.isConnected,
                builder: (context, isConnected, _) {
                  if (deviceProvider.selectedDevice == null) {
                    return const SizedBox.shrink();
                  }

                  return Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(
                        isConnected ? Icons.cast_connected : Icons.cast,
                        size: 18,
                        color: isConnected ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        deviceProvider.selectedDevice!.host,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
