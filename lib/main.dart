import 'dart:convert';
import 'dart:typed_data';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'services/device_discovery_service.dart';

void main() => runApp(const ViewerApp());

class ViewerApp extends StatefulWidget {
  const ViewerApp({super.key});
  @override
  State<ViewerApp> createState() => _ViewerAppState();
}

class _ViewerAppState extends State<ViewerApp> {
  WebSocketChannel? _channel;
  Uint8List? _lastFrame;
  String _status = 'Kliknij "Szukaj gogli" aby rozpocząć';
  final _discoveryService = DeviceDiscoveryService(discoveryPort: 8080);
  List<DiscoveredDevice> _devices = [];
  bool _isScanning = false;
  DiscoveredDevice? _selectedDevice;
  bool _drawerOpen = true;
  String _currentScreen = 'info'; // info, menu, game
  List<Map<String, dynamic>> _gameActions = [];
  final _manualIpController = TextEditingController();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  int _frameCount = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _discoveryService.dispose();
    _manualIpController.dispose();
    super.dispose();
  }

  void _startScanning() async {
    setState(() {
      _isScanning = true;
      _devices = [];
      _status = 'Skanowanie sieci HTTP (port 8080)... Szukam gogli VR';
    });

    try {
      await for (final device in _discoveryService.discoverDevices()) {
        if (!_isScanning) break; // Przerwij jeśli skanowanie zatrzymane
        setState(() {
          _devices.add(device);
          _status =
              'Znaleziono: ${_devices.length} urządzeń (skanowanie trwa...)';
        });
      }

      setState(() {
        _isScanning = false;
        if (_devices.isEmpty) {
          _status =
              'Nie znaleziono urządzeń. Sprawdź IP gogli i dodaj ręcznie.';
        } else {
          _status = 'Znaleziono ${_devices.length} urządzeń';
        }
      });
    } catch (e) {
      setState(() {
        _isScanning = false;
        _status = 'Błąd skanowania: $e';
      });
    }
  }

  void _connectManual() {
    var ip = _manualIpController.text.trim();
    if (ip.isEmpty) {
      setState(() => _status = 'Wprowadź adres IP');
      return;
    }

    // Usuń protokół jeśli użytkownik go wpisał
    if (ip.startsWith('http://')) ip = ip.substring(7);
    if (ip.startsWith('https://')) ip = ip.substring(8);
    if (ip.startsWith('ws://')) ip = ip.substring(5);
    if (ip.startsWith('wss://')) ip = ip.substring(6);
    // Usuń końcowy slash
    if (ip.endsWith('/')) ip = ip.substring(0, ip.length - 1);

    final manualDevice = DiscoveredDevice(
      name: 'VR Gogle (Ręczne)',
      host: ip,
      port: 9001,
      serviceType: 'manual',
    );

    setState(() {
      _selectedDevice = manualDevice;
      if (!_devices.any((d) => d.host == ip)) {
        _devices.add(manualDevice);
      }
    });

    _connect(manualDevice.wsUrl);
  }

  void _decodeFrameAsync(String base64Data) async {
    try {
      // Dekoduj w compute pool aby nie blokować UI thread
      final bytes = await compute(_decodeBase64, base64Data);
      if (mounted) {
        setState(() {
          _lastFrame = bytes;
          _status = 'Połączony (#$_frameCount)';
          _isScanning = false;
        });
      }
    } catch (e) {
      print('❌ Błąd dekodowania frame: $e');
    }
  }

  static Uint8List _decodeBase64(String base64Data) {
    return Uint8List.fromList(base64.decode(base64Data));
  }

  void _connect(String url) {
    try {
      print('🔗 Łączenie się z: $url');
      final ch = HtmlWebSocketChannel.connect(url);
      ch.innerWebSocket.binaryType = 'arraybuffer';
      print('✅ Kanał WebSocket utworzony');

      ch.stream.listen(
        (event) {
          print('📡 Otrzymano event: ${event.runtimeType}');
          // Obsługa binarnych danych (obrazy JPEG)
          if (event is Uint8List) {
            setState(() {
              _lastFrame = event;
              _status = 'Połączony (${event.length} B)';
              _isScanning = false;
            });
          } else if (event is ByteBuffer) {
            print('🖼️ ByteBuffer: ${event.lengthInBytes} bajtów');
            setState(() {
              _lastFrame = Uint8List.view(event);
              _status = 'Połączony (${event.lengthInBytes} B)';
              _isScanning = false;
            });
          } else if (event is List<int>) {
            print('🖼️ List<int>: ${event.length} bajtów');
            setState(() {
              _lastFrame = Uint8List.fromList(event);
              _status = 'Połączony (${event.length} B)';
              _isScanning = false;
            });
          }
          // Obsługa wiadomości tekstowych (JSON)
          else if (event is String) {
            _handleTextMessage(event);
          } else {
            print('❓ Nieznany typ eventu: ${event.runtimeType}');
          }
        },
        onDone: () {
          print('🔌 Stream zakończony');
          setState(() {
            _status = 'Rozłączony';
            _channel = null;
          });
        },
        onError: (e) {
          print('❌ Błąd streamu: $e');
          setState(() {
            _status = 'Błąd połączenia: $e';
            _channel = null;
          });
        },
      );

      print('✅ Stream listener dodany');
      setState(() {
        _channel = ch;
        _status = 'Połączony';
        _isScanning = false;
      });
    } catch (e) {
      print('❌ Wyjątek w _connect: $e');
      setState(() => _status = 'Wyjątek: $e');
    }
  }

  void _handleTextMessage(String message) {
    try {
      final data = json.decode(message);

      // Obsłuż różne typy wiadomości (gdy serwer wysyła JSON)
      if (data is Map<String, dynamic>) {
        final type = data['type'];

        switch (type) {
          case 'frame':
            final base64Data = data['data'] as String?;
            if (base64Data != null && base64Data.isNotEmpty) {
              _frameCount++;
              _decodeFrameAsync(base64Data);
            }
            break;
          case 'game_started':
            print('🎮 Gra rozpoczęta');
            final actions = data['actions'] as List<dynamic>?;
            final gameName = data['game'] as String?;
            setState(() {
              _currentScreen = 'game';
              _gameActions = actions?.cast<Map<String, dynamic>>() ?? [];
              print('🎮 Rozpoczęto grę: $gameName');
              print('🎮 Dostępne akcje: $_gameActions');
            });
            break;
          case 'available_games':
            print('🎮 Dostępne gry: ${data['games']}');
            // Przejdź do ekranu wyboru (menu) i ewentualnie zapisz listę gier
            setState(() {
              _currentScreen = 'menu';
            });
            break;
          case 'canvas_image':
            print('🖼️ Otrzymano obraz do zapisania (canvas_image)');
            _downloadCanvasImage(data);
            break;
          case 'action_completed':
            print('✅ Akcja zakończona sukcesem: ${data['action']}');

            // Sprawdź czy akcja zwróciła obraz do zapisania
            if (data.containsKey('image_base64')) {
              print('🖼️ Znaleziono dane obrazu w potwierdzeniu akcji');
              _downloadCanvasImage(data);
            }
            // Jeśli to była akcja zapisu, ale nie ma danych obrazu, zapisz ostatnią klatkę
            else if (data['action'] == 'save_canvas' && _lastFrame != null) {
              print('🖼️ Zapisywanie aktualnej klatki jako wynik save_canvas');
              _downloadCanvasImage({
                'image_base64': base64.encode(_lastFrame!),
                'format': 'jpg', // Stream jest zazwyczaj JPG
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              });
            }

            if (mounted) {
              _scaffoldMessengerKey.currentState?.showSnackBar(
                SnackBar(content: Text('Akcja wykonana: ${data['action']}')),
              );
            }
            break;
          case 'menu_state':
            final screen = data['screen'] as String?;
            print('📱 Stan menu: $screen');
            if (mounted) {
              setState(() {
                if (screen == 'game') {
                  _currentScreen = 'game';
                } else {
                  _currentScreen = 'menu';
                }
              });
            }
            break;
          default:
            print('❓ Nieznany typ wiadomości: $type');
        }
      }
    } catch (e) {
      // Jeśli nie da się zdekodować JSON, spróbuj rozpoznać surowy base64 lub data-URI
      final trimmed = message.trim();
      print('ℹ️ Otrzymano nie-JSON tekst: ${trimmed.length} zn.');

      // data:image/png;base64,...
      if (trimmed.startsWith('data:image')) {
        final parts = trimmed.split(',');
        final base64Part =
            parts.length > 1 ? parts.sublist(1).join(',') : parts[0];
        print('🖼️ Rozpoznano data-URI obrazu, zapisuję...');
        _downloadCanvasImage({
          'image_base64': base64Part,
          'format': 'png',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        return;
      }

      // Sprawdź, czy to wygląda jak base64 (prosty test: znaków base64 i długa długość)
      final candidate = trimmed.replaceAll(RegExp(r'\s+'), '');
      final base64Pattern = RegExp(r'^[A-Za-z0-9+/=]+$');
      if (candidate.length > 200 && base64Pattern.hasMatch(candidate)) {
        print(
          '🖼️ Rozpoznano prawdopodobny base64 obrazu, zapisuję jako png...',
        );
        _downloadCanvasImage({
          'image_base64': candidate,
          'format': 'png',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        return;
      }

      print('❌ Błąd parsowania JSON lub nieznany format wiadomości: $e');
    }
  }

  void sendMessage(Map<String, dynamic> message) {
    if (_channel == null) {
      print('❌ Brak połączenia WebSocket');
      return;
    }

    try {
      final jsonString = json.encode(message);
      _channel!.sink.add(jsonString);
      print('📤 Wysłano: $jsonString');
    } catch (e) {
      print('❌ Błąd wysyłania wiadomości: $e');
    }
  }

  void _downloadCanvasImage(Map<String, dynamic> data) {
    try {
      final base64Image = data['image_base64'] as String?;
      final format = data['format'] as String? ?? 'png';
      final timestamp = data['timestamp'] as num?;

      if (base64Image == null || base64Image.isEmpty) {
        print('❌ Brak danych obrazu');
        return;
      }

      // Tworzenie nazwy pliku z timestampem
      final fileName =
          'canvas_${timestamp?.toInt() ?? DateTime.now().millisecondsSinceEpoch}.$format';

      // Konwersja base64 do bytes
      final bytes = base64.decode(base64Image);

      // Tworzenie blob i pobieranie
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();

      html.Url.revokeObjectUrl(url);

      print('✅ Obraz zapisany: $fileName');

      // Pokaż komunikat użytkownikowi
      setState(() {
        _status = 'Obraz zapisany: $fileName';
      });
    } catch (e) {
      print('❌ Błąd zapisywania obrazu: $e');
      setState(() {
        _status = 'Błąd zapisywania obrazu';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _scaffoldMessengerKey,
      home: Scaffold(
        body: Row(
          children: [
            // Lewy panel boczny - menu/kontrolki
            if (_drawerOpen)
              Container(
                width: 260,
                decoration: BoxDecoration(color: Colors.grey.shade100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Nagłówek
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.blue.shade700),
                      child: Row(
                        children: [
                          Text(
                            'NEXT Dashboard',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () {
                              setState(() => _drawerOpen = false);
                            },
                            icon: const Icon(Icons.chevron_left),
                            color: Colors.white,
                            iconSize: 20,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),

                    // Sekcja wyszukiwania (ukryta gdy połączony)
                    if (_channel == null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'POŁĄCZENIE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade600,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _isScanning ? null : _startScanning,
                              icon: _isScanning
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.search, size: 18),
                              label: Text(
                                _isScanning ? 'Szukam...' : 'Szukaj gogli',
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'LUB WPROWADŹ IP',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade600,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _manualIpController,
                                    decoration: InputDecoration(
                                      hintText: '192.168.1.100',
                                      hintStyle: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade400,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Colors.blue.shade300,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: _connectManual,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                  child: const Icon(Icons.link, size: 18),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _isScanning
                                        ? Icons.hourglass_empty
                                        : _devices.isNotEmpty
                                            ? Icons.check_circle
                                            : Icons.info_outline,
                                    size: 18,
                                    color: _isScanning
                                        ? Colors.orange
                                        : _devices.isNotEmpty
                                            ? Colors.green
                                            : Colors.grey,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _status,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Lista urządzeń
                    if (_devices.isNotEmpty) ...[
                      Divider(height: 1, color: Colors.grey.shade300),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'URZĄDZENIA (${_devices.length})',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade600,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ..._devices.map((device) {
                              final isSelected = _selectedDevice == device;
                              final isConnected =
                                  _channel != null && isSelected;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  onTap: () {
                                    setState(() => _selectedDevice = device);
                                    _connect(device.wsUrl);
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.blue.shade50
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected
                                            ? Colors.blue.shade300
                                            : Colors.grey.shade300,
                                        width: isSelected ? 2 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isConnected
                                              ? Icons.cast_connected
                                              : Icons.cast,
                                          size: 18,
                                          color: isConnected
                                              ? Colors.green
                                              : Colors.grey.shade600,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                device.host,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.grey.shade800,
                                                ),
                                              ),
                                              Text(
                                                ':${device.port}',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isConnected)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                              color: Colors.green,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ],

                    // Sekcja kontroli - przyciski akcji
                    if (_channel != null) ...[
                      Divider(height: 1, color: Colors.grey.shade300),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'KONTROLA',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade600,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _currentScreen == 'info'
                                        ? Colors.blue.shade100
                                        : _currentScreen == 'menu'
                                            ? Colors.orange.shade100
                                            : Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _currentScreen == 'info'
                                        ? 'INFO'
                                        : _currentScreen == 'menu'
                                            ? 'MENU'
                                            : 'GRA',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: _currentScreen == 'info'
                                          ? Colors.blue.shade700
                                          : _currentScreen == 'menu'
                                              ? Colors.orange.shade700
                                              : Colors.green.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Przyciski dla ekranu INFO
                            if (_currentScreen == 'info') ...[
                              ElevatedButton.icon(
                                onPressed: () {
                                  // Przejście lokalne do ekranu menu oraz wysłanie komendy
                                  setState(() => _currentScreen = 'menu');
                                  sendMessage({'action': 'next'});
                                },
                                icon: const Icon(Icons.arrow_forward, size: 18),
                                label: const Text('Dalej'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],

                            // Przyciski dla ekranu MENU
                            if (_currentScreen == 'menu') ...[
                              ElevatedButton.icon(
                                onPressed: () =>
                                    sendMessage({'action': 'start_game_draw'}),
                                icon: const Icon(Icons.brush, size: 18),
                                label: const Text('Gra Rysunkowa'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: () => sendMessage({
                                  'action': 'start_game_forest_walk',
                                }),
                                icon: const Icon(Icons.nature, size: 18),
                                label: const Text('Spacer po Lesie'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],

                            // Przyciski dla ekranu GRY
                            if (_currentScreen == 'game') ...[
                              // Przyciski akcji gry (jeśli dostępne)
                              ..._gameActions.map((action) {
                                final actionId = action['id'] as String;
                                final actionName = action['name'] as String;

                                IconData icon;
                                Color color;

                                if (actionId == 'save_canvas') {
                                  icon = Icons.save;
                                  color = Colors.blue;
                                } else if (actionId == 'clear_canvas') {
                                  icon = Icons.clear;
                                  color = Colors.red;
                                } else {
                                  icon = Icons.touch_app;
                                  color = Colors.grey;
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: ElevatedButton.icon(
                                    onPressed: () =>
                                        sendMessage({'action': actionId}),
                                    icon: Icon(icon, size: 18),
                                    label: Text(actionName),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      backgroundColor: color,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                );
                              }).toList(),

                              // Przycisk wyjścia z gry
                              ElevatedButton.icon(
                                onPressed: () =>
                                    sendMessage({'action': 'exit_game'}),
                                icon: const Icon(Icons.exit_to_app, size: 18),
                                label: const Text('Wyjdź do Menu'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    const Spacer(),

                    // Stopka z info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Wymagania:',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '• Gogle VR włączone\n'
                            '• HTTP server (port 8080)\n'
                            '• WebSocket (port 9001)',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey.shade600,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Główna zawartość - podgląd wideo
            Expanded(
              child: Stack(
                children: [
                  Container(
                    color: const Color.fromARGB(255, 255, 255, 255),
                    child: Center(
                      child: _lastFrame == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.videocam_off,
                                  size: 64,
                                  color: Color.fromARGB(137, 144, 143, 143),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Czekam na pierwszą klatkę…',
                                  style: TextStyle(
                                    color: Color.fromARGB(137, 144, 143, 143),
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            )
                          : InteractiveViewer(
                              child: Image.memory(
                                _lastFrame!,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.low,
                                fit: BoxFit.contain,
                              ),
                            ),
                    ),
                  ),
                  // Przycisk toggle drawer
                  !_drawerOpen
                      ? Positioned(
                          top: 16,
                          left: 16,
                          child: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              onTap: () {
                                setState(() => _drawerOpen = !_drawerOpen);
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _drawerOpen
                                          ? Icons.menu_open
                                          : Icons.menu,
                                      size: 20,
                                      color: Colors.grey.shade700,
                                    ),
                                    if (!_drawerOpen &&
                                        _selectedDevice != null) ...[
                                      const SizedBox(width: 8),
                                      Icon(
                                        _channel != null
                                            ? Icons.cast_connected
                                            : Icons.cast,
                                        size: 18,
                                        color: _channel != null
                                            ? Colors.green
                                            : Colors.grey,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _selectedDevice!.host,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade800,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                      : SizedBox(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
