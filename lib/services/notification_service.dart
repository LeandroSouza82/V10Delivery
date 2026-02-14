import 'package:v10_delivery/services/supabase_service.dart';

class NotificationService {
  NotificationService._();

  /// Retorna a quantidade de avisos não lidos na tabela `avisos_gestor`.
  static Future<int> fetchUnreadCount() async {
    final dynamic q = await SupabaseService.client
        .from('avisos_gestor')
        .select('id')
        .eq('lida', false);
    if (q is List) return q.length;
    return 0;
  }

  /// Retorna todos os avisos do gestor (mais recentes primeiro).
  static Future<List<Map<String, dynamic>>> fetchAvisos() async {
    return await SupabaseService.fetchAvisosGestor();
  }
}
