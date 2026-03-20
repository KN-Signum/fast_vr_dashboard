import 'package:flutter/foundation.dart';
import '../services/device_discovery_service.dart';

class DeviceProvider with ChangeNotifier {
  final DeviceDiscoveryService _discoveryService = DeviceDiscoveryService(
    discoveryPort: 8080,
  );
  List<DiscoveredDevice> _devices = [];
  bool _isScanning = false;
  DiscoveredDevice? _selectedDevice;
  String _status = 'Kliknij "Szukaj gogli" aby rozpocząć';

  List<DiscoveredDevice> get devices => _devices;
  bool get isScanning => _isScanning;
  DiscoveredDevice? get selectedDevice => _selectedDevice;
  String get status => _status;

  void startScanning() async {
    _isScanning = true;
    _devices = [];
    _status = 'Skanowanie sieci HTTP (port 8080)... Szukam gogli VR';
    notifyListeners();

    try {
      await for (final device in _discoveryService.discoverDevices()) {
        if (!_isScanning) break;
        _devices.add(device);
        _status =
            'Znaleziono: ${_devices.length} urządzeń (skanowanie trwa...)';
        notifyListeners();
      }

      _isScanning = false;
      if (_devices.isEmpty) {
        _status = 'Nie znaleziono urządzeń. Sprawdź IP gogli i dodaj ręcznie.';
      } else {
        _status = 'Znaleziono ${_devices.length} urządzeń';
      }
      notifyListeners();
    } catch (e) {
      _isScanning = false;
      _status = 'Błąd skanowania: $e';
      notifyListeners();
    }
  }

  void stopScanning() {
    _isScanning = false;
    notifyListeners();
  }

  void selectDevice(DiscoveredDevice device) {
    _selectedDevice = device;
    notifyListeners();
  }

  void addManualDevice(String ip) {
    final manualDevice = DiscoveredDevice(
      name: 'VR Gogle (Ręczne)',
      host: ip,
      port: 8081,
      serviceType: 'manual',
    );
    _selectedDevice = manualDevice;
    if (!_devices.any((d) => d.host == ip)) {
      _devices.add(manualDevice);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _discoveryService.dispose();
    super.dispose();
  }
}
