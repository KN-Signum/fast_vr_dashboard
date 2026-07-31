import 'package:flutter_test/flutter_test.dart';
import 'package:vr_fast_dashboard/providers/eeg_control_provider.dart';
import 'package:vr_fast_dashboard/services/eeg_control_api.dart';

void main() {
  test('loads EEG state and sends runtime enable changes', () async {
    final api = FakeEegControlApi();
    final provider = EegControlProvider(api: api);

    await provider.refresh();

    expect(provider.hasLoaded, isTrue);
    expect(provider.enabled, isTrue);
    expect(provider.status, 'streaming');

    expect(await provider.setEnabled(false), isTrue);
    expect(api.requestedEnabled, false);
    expect(provider.enabled, isFalse);
    expect(provider.status, 'disabled');

    provider.dispose();
    expect(api.closed, isTrue);
  });

  test('does not enable EEG when backend mode is off', () async {
    final api = FakeEegControlApi(mode: 'off', enabled: false);
    final provider = EegControlProvider(api: api);

    await provider.refresh();

    expect(provider.isAvailable, isFalse);
    expect(await provider.setEnabled(true), isFalse);
    expect(api.requestedEnabled, isNull);
    provider.dispose();
  });
}

class FakeEegControlApi implements EegControlApi {
  String mode;
  bool enabled;
  bool? requestedEnabled;
  bool closed = false;

  FakeEegControlApi({this.mode = 'real', this.enabled = true});

  @override
  Future<Map<String, dynamic>> state() async => _state();

  @override
  Future<Map<String, dynamic>> setEnabled(bool enabled) async {
    requestedEnabled = enabled;
    this.enabled = enabled;
    return _state();
  }

  Map<String, dynamic> _state() => {
    'eeg_enabled': enabled,
    'eeg_mode': mode,
    'eeg_device_name': 'BA MINI TEST',
    'eeg_status': enabled ? 'streaming' : 'disabled',
    'eeg_error': null,
  };

  @override
  void close() => closed = true;
}
