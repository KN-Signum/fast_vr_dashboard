enum BirdSide { left, right }

class BirdCountState {
  int? visible;
  int? visibleLeft;
  int? visibleRight;
  int reportedLeft = 0;
  int reportedRight = 0;

  bool _inForest = false;

  void updateScene(String scene) {
    final entersForest = !_inForest && scene == 'forest';
    _inForest = scene == 'forest';
    if (entersForest) reset();
  }

  void updateVisible({required int total, int? left, int? right}) {
    visible = total.clamp(0, 1 << 31);
    if (left != null && right != null) {
      visibleLeft = left.clamp(0, 1 << 31);
      visibleRight = right.clamp(0, 1 << 31);
    } else {
      visibleLeft = null;
      visibleRight = null;
    }
  }

  bool adjustReported(BirdSide side, int delta) {
    if (!_inForest || delta == 0) return false;

    final current = side == BirdSide.left ? reportedLeft : reportedRight;
    final next = current + delta;
    if (next < 0) return false;

    if (side == BirdSide.left) {
      reportedLeft = next;
    } else {
      reportedRight = next;
    }
    return true;
  }

  void reset() {
    visible = null;
    visibleLeft = null;
    visibleRight = null;
    reportedLeft = 0;
    reportedRight = 0;
  }
}
