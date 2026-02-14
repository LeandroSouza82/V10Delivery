import 'package:flutter/material.dart';

/// Serviço minimal para notificações/avisos usado pela UI.
/// Implementação leve para satisfazer chamadas de UI durante análise.
class NotificationService {
  /// Inicializa o serviço de notificações (no futuro, pode configurar plugins)
  static Future<void> initialize() async {
    // placeholder: nada a fazer por enquanto
    return;
  }

  /// Recupera avisos não-lidos.
  /// Retorna uma lista de mapas representando os avisos.
  static Future<List<Map<String, dynamic>>> fetchAvisos() async {
    // placeholder: retornar lista vazia para evitar dependências externas
    return <Map<String, dynamic>>[];
  }

  /// Exibe uma notificação local simulada (placeholder)
  static Future<void> show(String title, String body) async {
    // placeholder: no-op
    debugPrint('NotificationService.show: $title - $body');
  }
}
