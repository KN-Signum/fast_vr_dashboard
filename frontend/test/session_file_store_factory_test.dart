import 'package:flutter_test/flutter_test.dart';
import 'package:vr_fast_dashboard/services/session_file_store_factory.dart';

void main() {
  test('platform file store exposes feature support safely', () {
    final store = createSessionFileStore();
    expect(store.isSupported, isA<bool>());
  });
}
