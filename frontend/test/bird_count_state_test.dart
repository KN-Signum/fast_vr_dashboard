import 'package:flutter_test/flutter_test.dart';
import 'package:vr_fast_dashboard/models/bird_count_state.dart';

void main() {
  test('preserves reports during refresh and resets for a new forest run', () {
    final state = BirdCountState();

    state.updateScene('forest');
    state.updateVisible(total: 8, left: 4, right: 4);
    expect(state.adjustReported(BirdSide.left, 1), isTrue);
    expect(state.adjustReported(BirdSide.right, 1), isTrue);
    expect(state.adjustReported(BirdSide.right, -1), isTrue);
    expect(state.adjustReported(BirdSide.right, -1), isFalse);

    state.updateScene('forest');
    expect(state.reportedLeft, 1);
    expect(state.visibleLeft, 4);

    state.updateScene('menu');
    state.updateScene('forest');
    expect(state.reportedLeft, 0);
    expect(state.visible, isNull);
  });

  test('accepts a legacy total-only bird payload', () {
    final state = BirdCountState()
      ..updateVisible(total: 5, left: null, right: null);

    expect(state.visible, 5);
    expect(state.visibleLeft, isNull);
    expect(state.visibleRight, isNull);
  });
}
