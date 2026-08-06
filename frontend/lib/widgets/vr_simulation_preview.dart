import 'dart:convert';

import 'package:flutter/material.dart';

import '../providers/vr_simulation_provider.dart';
import '../theme/app_style.dart';

class VrSimulationPreview extends StatelessWidget {
  final VrSimulationProvider simulation;

  const VrSimulationPreview({super.key, required this.simulation});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: simulation,
      builder: (context, _) => _buildPreview(),
    );
  }

  Widget _buildPreview() {
    final response =
        simulation.noResponseMessage ??
        (simulation.lastResponses.isEmpty
            ? 'Oczekiwanie na komendę z panelu.'
            : const JsonEncoder.withIndent(
                '  ',
              ).convert(_displayResponses(simulation.lastResponses)));

    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        key: const ValueKey('vr-simulation-preview'),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const StatusPill(
                  label: 'SYMULACJA VR',
                  online: true,
                  icon: Icons.science,
                ),
                const Spacer(),
                Text(
                  simulation.connected ? 'POŁĄCZONO' : 'ŁĄCZENIE',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              _screenLabel(simulation.currentScreen),
              key: const ValueKey('vr-simulation-screen-name'),
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ekran Unity: ${simulation.currentScreen}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            _simulationField(
              'OSTATNIA KOMENDA',
              simulation.lastCommand ?? 'Brak',
              const ValueKey('vr-simulation-last-command'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _simulationField(
                'OCZEKIWANA ODPOWIEDŹ VR',
                response,
                const ValueKey('vr-simulation-response'),
                scrollable: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _simulationField(
    String label,
    String value,
    Key key, {
    bool scrollable = false,
  }) {
    final content = SelectableText(
      value,
      key: key,
      style: const TextStyle(
        color: AppColors.text,
        fontSize: 12,
        fontFamily: 'monospace',
        height: 1.45,
      ),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (scrollable)
            Expanded(child: SingleChildScrollView(child: content))
          else
            content,
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _displayResponses(
    List<Map<String, dynamic>> responses,
  ) {
    return responses
        .map((response) {
          final display = Map<String, dynamic>.from(response);
          if (display.containsKey('image_base64')) {
            display['image_base64'] = '<dane obrazu JPEG base64>';
          }
          return display;
        })
        .toList(growable: false);
  }

  String _screenLabel(String screen) => switch (screen) {
    'info' => 'EKRAN INFORMACYJNY',
    'menu' => 'WYBÓR ĆWICZENIA',
    'forest' => 'SPACER W LESIE',
    'painting' => 'MALOWANIE',
    _ => screen.toUpperCase(),
  };
}
