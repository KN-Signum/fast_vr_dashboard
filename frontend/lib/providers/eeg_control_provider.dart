import 'package:flutter/foundation.dart';

import '../services/eeg_control_api.dart';

class EegControlProvider with ChangeNotifier {
  final EegControlApi _api;

  bool _enabled = true;
  bool _hasLoaded = false;
  bool _isRefreshing = false;
  bool _isBusy = false;
  String _mode = 'real';
  String _status = 'connecting';
  String _deviceName = '';
  String? _eegError;
  String? _requestError;

  EegControlProvider({required EegControlApi api}) : _api = api;

  bool get enabled => _enabled;
  bool get hasLoaded => _hasLoaded;
  bool get isBusy => _isBusy;
  bool get isAvailable => _mode != 'off';
  String get mode => _mode;
  String get status => _status;
  String get deviceName => _deviceName;
  String? get eegError => _eegError;
  String? get requestError => _requestError;

  Future<void> refresh() async {
    if (_isRefreshing || _isBusy) return;
    _isRefreshing = true;
    try {
      _apply(await _api.state());
      _requestError = null;
    } on EegControlApiException catch (error) {
      _requestError = error.message;
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<bool> setEnabled(bool enabled) async {
    if (_isBusy || !_hasLoaded || !isAvailable || enabled == _enabled) {
      return false;
    }
    _isBusy = true;
    _requestError = null;
    notifyListeners();
    try {
      _apply(await _api.setEnabled(enabled));
      return true;
    } on EegControlApiException catch (error) {
      _requestError = error.message;
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void _apply(Map<String, dynamic> state) {
    _enabled = state['eeg_enabled'] as bool? ?? _enabled;
    _mode = state['eeg_mode'] as String? ?? _mode;
    _status = state['eeg_status'] as String? ?? _status;
    _deviceName = state['eeg_device_name'] as String? ?? _deviceName;
    _eegError = state['eeg_error'] as String?;
    _hasLoaded = true;
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }
}
