import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'splash_page.dart';
import 'globals.dart';

class AdminApprovalPage extends StatefulWidget {
  const AdminApprovalPage({super.key});

  @override
  State<AdminApprovalPage> createState() => _AdminApprovalPageState();
}

class _AdminApprovalPageState extends State<AdminApprovalPage> {
  late Future<List<Map<String, dynamic>>> _futurePendentes;

  @override
  void initState() {
    super.initState();
    _futurePendentes = _fetchPendentes();
  }

  Future<List<Map<String, dynamic>>> _fetchPendentes() async {
    final client = Supabase.instance.client;
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

  Future<void> _approve(int id) async {
    try {
      final client = Supabase.instance.client;
      await client
          .from('motoristas')
          .update({'acesso': 'aprovado'})
          .eq('id', id);
      // res may be a list or map; we consider success if no error thrown
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Motorista aprovado.'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _futurePendentes = _fetchPendentes();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao aprovar: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aprovação de Motoristas'),
        actions: [
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              try {
                final prefs = await SharedPreferences.getInstance();
                try {
                  await prefs.setBool('manter_logado', false);
                } catch (_) {}
                try {
                  await prefs.remove('driver_id');
                  await prefs.remove('driver_name');
                } catch (_) {}
                idLogado = null;
                nomeMotorista = '';
              } catch (_) {}
              if (!mounted) return;
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const SplashPage()),
                (route) => false,
              );
            },
            child: const Text('Sair', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _futurePendentes,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Erro: ${snap.error}'));
          }
          final list = snap.data ?? <Map<String, dynamic>>[];
          if (list.isEmpty) {
            return const Center(child: Text('Nenhum motorista pendente.'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = list[index];
              final idRaw = item['id'];
              final int id = idRaw is int
                  ? idRaw
                  : int.tryParse(idRaw.toString()) ?? 0;
              final nome = (item['nome'] ?? '').toString();
              final cpf = (item['cpf'] ?? '').toString();
              final email = (item['email'] ?? '').toString();
              final subtitle = cpf.isNotEmpty ? cpf : email;
              return ListTile(
                title: Text(nome),
                subtitle: Text(subtitle),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  onPressed: () => _approve(id),
                  child: const Text('Aprovar'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
