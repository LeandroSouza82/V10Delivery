import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Serviço responsável por persistir ações (sucesso/falha) localmente quando
/// não há conectividade e sincronizá-las com o Supabase assim que houver rede.
class OfflineSyncService {
  static const String _key = 'fila_offline_entregas';

  /// Salva uma ação pendente no dispositivo quando o envio ao Supabase falha.
  /// [lat] e [lng] são as coordenadas do motorista no momento da ocorrência.
  static Future<void> salvarAcaoOffline(
    String pedidoId,
    String statusDesejado, {
    double? lat,
    double? lng,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> fila = prefs.getStringList(_key) ?? [];
      final acao = jsonEncode({
        'id': pedidoId,
        'status': statusDesejado,
        if (lat != null) 'lat_conclusao': lat,
        if (lng != null) 'lng_conclusao': lng,
      });
      fila.add(acao);
      await prefs.setStringList(_key, fila);
    } catch (e) {
      // ignorar — não podemos fazer mais nada sem rede e sem storage
    }
  }

  /// Tenta reenviar todas as ações que estavam presas no dispositivo.
  /// Deve ser chamado ao detectar que a conexão foi restaurada.
  static Future<void> sincronizarPendentes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> fila = prefs.getStringList(_key) ?? [];
      if (fila.isEmpty) return;

      final supabase = Supabase.instance.client;
      final List<String> falhasRestantes = [];

      for (final item in fila) {
        try {
          final map = jsonDecode(item) as Map<String, dynamic>;
          final payload = <String, dynamic>{'status': map['status']};
          if (map['lat_conclusao'] != null) {
            payload['lat_conclusao'] = map['lat_conclusao'];
          }
          if (map['lng_conclusao'] != null) {
            payload['lng_conclusao'] = map['lng_conclusao'];
          }
          await supabase.from('entregas').update(payload).eq('id', map['id']);
        } catch (_) {
          // ainda sem internet — mantém na fila
          falhasRestantes.add(item);
        }
      }

      await prefs.setStringList(_key, falhasRestantes);
    } catch (_) {}
  }
}
