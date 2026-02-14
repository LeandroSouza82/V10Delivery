import 'package:flutter/foundation.dart';

/// Logger seguro para ambiente de release.
/// Em release (kReleaseMode == true) não emite nada.
void dlog(Object? message) {
  if (!kReleaseMode) {
    debugPrint(message?.toString());
  }
}
