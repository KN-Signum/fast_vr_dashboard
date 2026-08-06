import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/web_socket_provider.dart';
import '../providers/eye_tracking_provider.dart';
import '../providers/vr_simulation_provider.dart';
import '../theme/app_style.dart';
import 'eye_tracking_overlay.dart';
import 'session_timeline.dart';
import 'vr_simulation_preview.dart';

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
    final vrSimulation = context.watch<VrSimulationProvider>();

    return Expanded(
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  color: AppColors.viewer,
                  child: Center(
                    child: vrSimulation.enabled
                        ? _buildSimulationPreview(vrSimulation)
                        : Selector<WebSocketProvider, Uint8List?>(
                            selector: (_, provider) => provider.lastFrame,
                            builder: (context, frame, _) {
                              if (frame == null) {
                                return _buildPlaceholder();
                              }

                              return _buildPreviewWithEyeTracking(
                                context,
                                frame,
                              );
                            },
                          ),
                  ),
                ),
                if (!isDrawerOpen)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: _buildFloatingMenuButton(context),
                  ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: _buildEyeTrackingToggle(context),
                ),
              ],
            ),
          ),
          const SessionTimeline(),
        ],
      ),
    );
  }

  Widget _buildSimulationPreview(VrSimulationProvider simulation) {
    return VrSimulationPreview(simulation: simulation);
  }

  /// Build game preview with eye tracking overlay
  Widget _buildPreviewWithEyeTracking(BuildContext context, Uint8List frame) {
    final eyeTrackingProvider = context.watch<EyeTrackingProvider>();

    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 30,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Game preview image
            Image.memory(
              frame,
              gaplessPlayback: true, // Kluczowe: zapobiega mruganiu
              filterQuality:
                  FilterQuality.low, // Wyższa wydajność w przeglądarce
              fit: BoxFit.contain,
              alignment: Alignment.center,
            ),

            // Eye tracking overlay
            LayoutBuilder(
              builder: (context, constraints) {
                return EyeTrackingVisualizationLayer(
                  eyeTrackingProvider: eyeTrackingProvider,
                  previewSize: constraints.biggest,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Widget zastępczy, gdy nie ma obrazu
  Widget _buildPlaceholder() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF18212F),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.monitor, size: 58, color: Color(0xFF94A3B8)),
            SizedBox(height: 14),
            Text(
              'Oczekiwanie na podgląd VR',
              style: TextStyle(
                color: Color(0xFFE2E8F0),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Podgląd pojawi się, gdy gogle wyślą klatki obrazu.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // Eye Tracking Toggle Button
  Widget _buildEyeTrackingToggle(BuildContext context) {
    final eyeTrackingProvider = context.watch<EyeTrackingProvider>();
    final isEnabled = eyeTrackingProvider.isEnabled;
    final isReceiving = eyeTrackingProvider.isReceiving;
    final statusColor = !isEnabled
        ? Colors.white
        : isReceiving
        ? AppColors.success
        : AppColors.warning;
    final foregroundColor = isEnabled ? Colors.white : AppColors.muted;
    final label = !isEnabled
        ? 'ET: WYŁ.'
        : isReceiving
        ? 'ET: AKTYWNE'
        : 'ET: BRAK DANYCH';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          eyeTrackingProvider.toggleEyeTracking();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isEnabled
                ? statusColor.withValues(alpha: 0.94)
                : Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isEnabled
                  ? statusColor
                  : Colors.white.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.remove_red_eye, size: 18, color: foregroundColor),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: foregroundColor,
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
  Widget _buildFloatingMenuButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggleDrawer,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu, size: 20, color: AppColors.text),
              Selector<WebSocketProvider, bool>(
                selector: (_, provider) => provider.isConnected,
                builder: (context, isConnected, _) {
                  if (!isConnected) {
                    return const SizedBox.shrink();
                  }

                  return Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(
                        isConnected ? Icons.cast_connected : Icons.cast,
                        size: 18,
                        color: isConnected
                            ? AppColors.success
                            : AppColors.muted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Serwer',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.text,
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
