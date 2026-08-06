import 'session_file_store.dart';
import 'session_file_store_stub.dart'
    if (dart.library.js_interop) 'session_file_store_web.dart'
    as platform;

SessionFileStore createSessionFileStore() {
  return platform.createPlatformSessionFileStore();
}
