import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class DiscoveredDevice {
  final String name;
  final String host;
  final int port;
  final String serviceType;

  DiscoveredDevice({
    required this.name,
    required this.host,
    required this.port,
    required this.serviceType,
  });

  String get wsUrl => 'ws://$host:$port';

  @override
  String toString() => '$name ($host:$port)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredDevice &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port;

  @override
  int get hashCode => host.hashCode ^ port.hashCode;
}

class DeviceDiscoveryService {
  final int _discoveryPort;
  final List<String> _subnetPrefixes;

  DeviceDiscoveryService({
    int discoveryPort = 8080,
    List<String>? subnetPrefixes,
  })  : _discoveryPort = discoveryPort,
        _subnetPrefixes = subnetPrefixes ?? ['192.168.100', '192.168.56'];

  /// Skanowanie sieci w poszukiwaniu urządzeń VR
  /// Na platformie web próbuje połączyć się z popularnymi adresami
  Stream<DiscoveredDevice> discoverDevices() async* {
    if (kIsWeb) {
      // Dla platformy webowej: próbkowanie znanych adresów
      yield* _scanWebDevices();
    } else {
      // Dla natywnych platform można by użyć mDNS
      // (wymagałoby importu warunkowego multicast_dns)
      yield* _scanWebDevices();
    }
  }

  /// Skanowanie dla platformy webowej - HTTP discovery
  Stream<DiscoveredDevice> _scanWebDevices() async* {
    final Set<DiscoveredDevice> discoveredDevices = {};

    // Najpierw localhost
    print('Scanning localhost...');
    var device = await _tryHttpDiscovery('localhost');
    if (device != null && !discoveredDevices.contains(device)) {
      discoveredDevices.add(device);
      yield device;
    }

    device = await _tryHttpDiscovery('127.0.0.1');
    if (device != null && !discoveredDevices.contains(device)) {
      discoveredDevices.add(device);
      yield device;
    }

    // Skanuj najpopularniejsze adresy w każdej podsieci
    final priorityHosts = [1, 2, 10, 20, 50, 100, 101, 102, 150, 200];

    for (final prefix in _subnetPrefixes) {
      print('Scanning $prefix.x...');

      // Najpierw priorytetowe adresy
      for (final i in priorityHosts) {
        final host = '$prefix.$i';
        device = await _tryHttpDiscovery(host);
        if (device != null && !discoveredDevices.contains(device)) {
          discoveredDevices.add(device);
          yield device;
        }
      }

      // Potem reszta
      for (int i = 3; i <= 254; i++) {
        if (priorityHosts.contains(i)) continue;

        final host = '$prefix.$i';
        device = await _tryHttpDiscovery(host);
        if (device != null && !discoveredDevices.contains(device)) {
          discoveredDevices.add(device);
          yield device;
        }

        // Małe opóźnienie co kilka prób
        if (i % 30 == 0) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    }

    print('Scanning complete');
  }

  /// Próbuje wysłać HTTP GET do discovery endpoint
  Future<DiscoveredDevice?> _tryHttpDiscovery(String host) async {
    try {
      final url = Uri.parse('http://$host:$_discoveryPort/discover');

      final response = await http.get(url).timeout(
            const Duration(milliseconds: 200),
            onTimeout: () => throw TimeoutException('HTTP timeout'),
          );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        return DiscoveredDevice(
          name: data['name'] ?? 'VR Goggles ($host)',
          host: data['ip'] ?? host,
          port: data['port'] ?? 9001,
          serviceType: data['type'] ?? 'vr_goggles',
        );
      }

      return null;
    } catch (e) {
      // Połączenie nie powiodło się - to normalne podczas skanowania
      return null;
    }
  }

  /// Jednorazowe skanowanie - zwraca listę wszystkich wykrytych urządzeń
  Future<List<DiscoveredDevice>> scanOnce() async {
    final devices = <DiscoveredDevice>[];
    await for (final device in discoverDevices()) {
      devices.add(device);
    }
    return devices;
  }

  void dispose() {
    // Cleanup jeśli potrzebny
  }
}
