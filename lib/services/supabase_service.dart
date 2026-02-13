import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Initialize Supabase using environment variables from .env
class SupabaseService {
  SupabaseService._();

  static final SupabaseClient client = Supabase.instance.client;

  static Future<void> initializeFromEnv() async {
    final url = dotenv.env['SUPABASE_URL'] ?? '';
    final anon = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
    if (url.isEmpty || anon.isEmpty) {
      throw Exception('Supabase keys are not set in .env');
    }
    await Supabase.initialize(url: url, anonKey: anon);
  }

  /// Exemplo: desloga o usuário
  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  /// Atualiza localização do motorista
  static Future<void> updateMotoristaLocation(
    String motoristaId,
    double latitude,
    double longitude, {
    String status = 'disponivel',
    bool estaOnline = true,
  }) async {
    try {
      await client
          .from('motoristas')
          .update({
            'lat': latitude.toString(),
            'lng': longitude.toString(),
            'status': status,
            'esta_online': estaOnline,
            'ultima_atualizacao': DateTime.now().toIso8601String(),
          })
          .eq('id', motoristaId);
    } catch (e) {
      rethrow;
    }
  }

  // TODO: mover aqui toda a lógica de banco (queries, realtime, auth helpers)
}
