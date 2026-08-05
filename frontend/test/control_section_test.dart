import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vr_fast_dashboard/widgets/easel_direction_pad.dart';

void main() {
  testWidgets('easel direction buttons send their matching actions', (
    tester,
  ) async {
    final actions = <String>[];
    const availableActions = {
      'move_easel_left',
      'move_easel_right',
      'move_easel_up',
      'move_easel_down',
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EaselDirectionPad(
            availableActions: availableActions,
            onAction: actions.add,
          ),
        ),
      ),
    );

    for (final action in availableActions) {
      await tester.tap(find.byKey(ValueKey(action)));
    }

    expect(actions, availableActions.toList());
  });

  testWidgets('easel direction buttons use a stable directional layout', (
    tester,
  ) async {
    const availableActions = {
      'move_easel_left',
      'move_easel_right',
      'move_easel_up',
      'move_easel_down',
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EaselDirectionPad(
            availableActions: availableActions,
            onAction: (_) {},
          ),
        ),
      ),
    );

    final left = tester.getCenter(
      find.byKey(const ValueKey('move_easel_left')),
    );
    final right = tester.getCenter(
      find.byKey(const ValueKey('move_easel_right')),
    );
    final up = tester.getCenter(find.byKey(const ValueKey('move_easel_up')));
    final down = tester.getCenter(
      find.byKey(const ValueKey('move_easel_down')),
    );

    expect(left.dx, lessThan(right.dx));
    expect(left.dy, right.dy);
    expect(up.dy, lessThan(left.dy));
    expect(down.dy, greaterThan(left.dy));
    expect(up.dx, down.dx);
  });
}
