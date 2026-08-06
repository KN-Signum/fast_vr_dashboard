import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_style.dart';
import 'solitaire_game.dart';

class SolitaireOverlay extends StatefulWidget {
  final bool visible;
  final VoidCallback onClose;

  const SolitaireOverlay({
    super.key,
    required this.visible,
    required this.onClose,
  });

  @override
  State<SolitaireOverlay> createState() => _SolitaireOverlayState();
}

class _SolitaireOverlayState extends State<SolitaireOverlay> {
  int _gameNumber = 0;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.visible,
      child: Offstage(
        offstage: !widget.visible,
        child: Material(
          color: Colors.black.withValues(alpha: 0.42),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('solitaire-barrier'),
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onClose,
                ),
              ),
              Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 600;
                    final margin = compact ? 0.0 : 24.0;
                    final width = math.min(
                      1000.0,
                      constraints.maxWidth - margin * 2,
                    );
                    final height = math.min(
                      760.0,
                      constraints.maxHeight - margin * 2,
                    );

                    return GestureDetector(
                      onTap: () {},
                      child: Container(
                        key: const ValueKey('solitaire-dialog'),
                        width: width,
                        height: height,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(compact ? 0 : 8),
                          border: compact
                              ? null
                              : Border.all(color: AppColors.border),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 28,
                              offset: Offset(0, 12),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            SizedBox(
                              height: 58,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.style_outlined,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        'Pasjans',
                                        style: TextStyle(
                                          color: AppColors.text,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Tooltip(
                                      message: 'Nowa gra',
                                      child: IconButton(
                                        key: const ValueKey(
                                          'solitaire-new-game',
                                        ),
                                        onPressed: () =>
                                            setState(() => _gameNumber++),
                                        icon: const Icon(Icons.refresh),
                                      ),
                                    ),
                                    Tooltip(
                                      message: 'Zamknij',
                                      child: IconButton(
                                        key: const ValueKey('solitaire-close'),
                                        onPressed: widget.onClose,
                                        icon: const Icon(Icons.close),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: SolitaireGame(
                                key: const ValueKey('solitaire-game'),
                                gameNumber: _gameNumber,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
