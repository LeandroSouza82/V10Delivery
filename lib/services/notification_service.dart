import 'package:flutter/services.dart';

class NotificationService {
  static const MethodChannel _channel = MethodChannel('app.channel.launcher');

  /// Solicita ao código nativo que crie o canal 'pedidos' com o som dado (sem extensão)
  Future<void> init() async {
    try {
      await _channel.invokeMethod('createPedidosChannel', {'sound': 'buzina'});
    } catch (_) {
      // ignore errors; native may already have created the channel
    }
  }
}
