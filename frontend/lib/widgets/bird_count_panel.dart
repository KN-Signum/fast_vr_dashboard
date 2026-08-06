import 'package:flutter/material.dart';

import '../theme/app_style.dart';

class BirdCountPanel extends StatelessWidget {
  const BirdCountPanel({
    required this.visible,
    required this.reportedLeft,
    required this.reportedRight,
    required this.onIncrementLeft,
    required this.onDecrementLeft,
    required this.onIncrementRight,
    required this.onDecrementRight,
    this.visibleLeft,
    this.visibleRight,
    super.key,
  });

  final int visible;
  final int? visibleLeft;
  final int? visibleRight;
  final int reportedLeft;
  final int reportedRight;
  final VoidCallback onIncrementLeft;
  final VoidCallback onDecrementLeft;
  final VoidCallback onIncrementRight;
  final VoidCallback onDecrementRight;

  bool get _hasSideCounts => visibleLeft != null && visibleRight != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.flutter_dash, size: 16, color: Colors.teal),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Widoczne ptaki',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$visible',
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (_hasSideCounts) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 7),
              child: Divider(height: 1),
            ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _BirdSideCounter(
                      label: 'LEWA STRONA',
                      visible: visibleLeft!,
                      reported: reportedLeft,
                      onIncrement: onIncrementLeft,
                      onDecrement: reportedLeft > 0 ? onDecrementLeft : null,
                    ),
                  ),
                  const VerticalDivider(width: 9, thickness: 1),
                  Expanded(
                    child: _BirdSideCounter(
                      label: 'PRAWA STRONA',
                      visible: visibleRight!,
                      reported: reportedRight,
                      onIncrement: onIncrementRight,
                      onDecrement: reportedRight > 0 ? onDecrementRight : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BirdSideCounter extends StatelessWidget {
  const _BirdSideCounter({
    required this.label,
    required this.visible,
    required this.reported,
    required this.onIncrement,
    required this.onDecrement,
  });

  final String label;
  final int visible;
  final int reported;
  final VoidCallback onIncrement;
  final VoidCallback? onDecrement;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 8,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Wygenerowane: $visible',
          maxLines: 1,
          style: const TextStyle(color: AppColors.muted, fontSize: 8),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CounterButton(
              tooltip: 'Cofnij zgłoszenie',
              icon: Icons.remove,
              onPressed: onDecrement,
            ),
            SizedBox(
              width: 18,
              child: Text(
                '$reported',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _CounterButton(
              tooltip: 'Dodaj zauważonego ptaka',
              icon: Icons.add,
              onPressed: onIncrement,
              emphasized: true,
            ),
          ],
        ),
        const SizedBox(height: 2),
        const Text(
          'zgłoszone',
          style: TextStyle(color: AppColors.muted, fontSize: 8),
        ),
      ],
    );
  }
}

class _CounterButton extends StatelessWidget {
  const _CounterButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.emphasized = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 24,
        height: 24,
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 24, height: 24),
          style: IconButton.styleFrom(
            fixedSize: const Size.square(24),
            minimumSize: const Size.square(24),
            maximumSize: const Size.square(24),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            backgroundColor: emphasized && enabled
                ? AppColors.primary
                : AppColors.surface,
            foregroundColor: emphasized && enabled
                ? Colors.white
                : AppColors.primary,
            disabledBackgroundColor: AppColors.surface,
            disabledForegroundColor: AppColors.muted.withValues(alpha: 0.5),
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 14),
        ),
      ),
    );
  }
}
