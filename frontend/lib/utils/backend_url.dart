String resolveBackendWebSocketUrl(
  Uri base, {
  bool useDevelopmentBackend = false,
  String role = 'dashboard',
}) {
  if (useDevelopmentBackend) {
    return 'ws://127.0.0.1:8080/ws?role=$role';
  }

  if (base.scheme != 'http' && base.scheme != 'https') {
    return 'ws://127.0.0.1:8080/ws?role=$role';
  }

  final host = base.host.isEmpty ? '127.0.0.1' : base.host;
  final scheme = base.scheme == 'https' ? 'wss' : 'ws';
  return Uri(
    scheme: scheme,
    host: host,
    port: base.hasPort ? base.port : null,
    path: '/ws',
    queryParameters: {'role': role},
  ).toString();
}

Uri resolveBackendHttpBase(Uri base, {bool useDevelopmentBackend = false}) {
  if (useDevelopmentBackend ||
      (base.scheme != 'http' && base.scheme != 'https')) {
    return Uri.parse('http://127.0.0.1:8080');
  }

  return Uri(
    scheme: base.scheme,
    host: base.host.isEmpty ? '127.0.0.1' : base.host,
    port: base.hasPort ? base.port : null,
  );
}
