import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

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

  /// Helper para login com Google (web)
  static Future<void> signInWithGoogleWeb() async {
    try {
      await client.auth.signInWithOAuth(OAuthProvider.google);
    } catch (e) {
      rethrow;
    }
  }

  /// Realiza login com email e senha usando o client do Supabase.
  static Future<void> login(String email, String password) async {
    try {
      await client.auth.signInWithPassword(email: email, password: password);
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  /// Insere um novo motorista na tabela `motoristas` com status 'pendente'.
  /// Retorna a resposta bruta do Supabase (pode ser List ou Map).
  static Future<dynamic> signUpMotorista({
    required String nome,
    required String sobrenome,
    required String cpf,
    required String telefone,
    required String email,
    required String senha,
  }) async {
    return await client.from('motoristas').insert({
      'nome': nome,
      'sobrenome': sobrenome,
      'cpf': cpf,
      'telefone': telefone,
      'email': email,
      'senha': senha,
      'acesso': 'pendente',
    }).select();
  }

  /// Retorna a lista de motoristas com acesso = 'pendente'.
  static Future<List<Map<String, dynamic>>> fetchPendingMotoristas() async {
    final dynamic q = await client
        .from('motoristas')
        .select('id,nome,cpf,email,telefone')
        .eq('acesso', 'pendente')
        .order('created_at', ascending: true);
    if (q is List) {
      return List<Map<String, dynamic>>.from(q.cast<Map<String, dynamic>>());
    }
    return <Map<String, dynamic>>[];
  }

  /// Aprova um motorista (altera acesso para 'aprovado').
  static Future<void> approveMotorista(int id) async {
    await client.from('motoristas').update({'acesso': 'aprovado'}).eq('id', id);
  }

  /// Busca avisos do gestor.
  static Future<List<Map<String, dynamic>>> fetchAvisosGestor() async {
    final dynamic q = await client
        .from('avisos_gestor')
        .select('*')
        .order('created_at', ascending: false);
    if (q is List) {
      return List<Map<String, dynamic>>.from(q.cast<Map<String, dynamic>>());
    }
    return <Map<String, dynamic>>[];
  }

  /// Alterna o campo `lida` de um aviso.
  static Future<void> toggleAvisoLido(dynamic id, bool marcado) async {
    await client.from('avisos_gestor').update({'lida': marcado}).eq('id', id);
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

  // NOTE: `relatorios_entrega` helper removed — this table/column is not present in the
  // current schema. Keep Supabase actions limited to existing tables.

  // Centraliza a lógica de banco (queries, realtime, auth helpers)
}
