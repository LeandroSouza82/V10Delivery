// Stub for platforms where `dart:io` is not available (Web).
// This file is conditionally imported in `main.dart` so code that
// references `File` or `SocketException` can still compile on Web.

class File {
  final String path;
  File(this.path);
  Future<bool> exists() async => false;
}

class SocketException implements Exception {}
