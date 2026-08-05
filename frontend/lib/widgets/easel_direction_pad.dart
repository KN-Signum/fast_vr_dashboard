import 'package:flutter/material.dart';

import '../theme/app_style.dart';

class EaselDirectionPad extends StatelessWidget {
  final Set<String> availableActions;
  final ValueChanged<String> onAction;

  const EaselDirectionPad({
    required this.availableActions,
    required this.onAction,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SectionPanel(
      padding: const EdgeInsets.all(12),
      color: AppColors.surfaceAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Pozycja sztalugi',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: SizedBox(
              width: 142,
              child: Column(
                children: [
                  _directionRow(
                    const SizedBox.square(dimension: 42),
                    _directionButton(
                      action: 'move_easel_up',
                      icon: Icons.arrow_upward,
                      tooltip: 'Podnieś sztalugę',
                    ),
                    const SizedBox.square(dimension: 42),
                  ),
                  const SizedBox(height: 6),
                  _directionRow(
                    _directionButton(
                      action: 'move_easel_left',
                      icon: Icons.arrow_back,
                      tooltip: 'Przesuń sztalugę w lewo',
                    ),
                    const SizedBox.square(dimension: 42),
                    _directionButton(
                      action: 'move_easel_right',
                      icon: Icons.arrow_forward,
                      tooltip: 'Przesuń sztalugę w prawo',
                    ),
                  ),
                  const SizedBox(height: 6),
                  _directionRow(
                    const SizedBox.square(dimension: 42),
                    _directionButton(
                      action: 'move_easel_down',
                      icon: Icons.arrow_downward,
                      tooltip: 'Obniż sztalugę',
                    ),
                    const SizedBox.square(dimension: 42),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _directionRow(Widget left, Widget center, Widget right) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [left, center, right],
    );
  }

  Widget _directionButton({
    required String action,
    required IconData icon,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 42,
        child: IconButton.outlined(
          key: ValueKey(action),
          onPressed: availableActions.contains(action)
              ? () => onAction(action)
              : null,
          icon: Icon(icon, size: 20),
        ),
      ),
    );
  }
}
