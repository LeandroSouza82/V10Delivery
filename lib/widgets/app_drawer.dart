import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:v10_delivery/screens/splash_screen.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  String _nome = 'Motorista';

  @override
  void initState() {
    super.initState();
    _loadNome();
  }

  Future<void> _loadNome() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('driver_name');
      if (saved != null && saved.isNotEmpty) {
        setState(() => _nome = saved);
        return;
      }

      final uuid = prefs.getString('driver_uuid');
      if (uuid != null && uuid.isNotEmpty) {
        try {
          final resp = await Supabase.instance.client
              .from('motoristas')
              .select('nome')
              .eq('uuid', uuid)
              .limit(1)
              .maybeSingle();
          if (resp != null) {
            final nome = (resp as Map)['nome']?.toString() ?? '';
            if (nome.isNotEmpty) {
              setState(() => _nome = nome);
              await prefs.setString('driver_name', nome);
              return;
            }
          }
        } catch (_) {
          // ignore errors; fallback to Supabase user metadata next
        }
      }

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final meta = user.userMetadata ?? <String, dynamic>{};
        final nomeMeta = meta['nome'] ?? meta['name'] ?? meta['full_name'];
        if (nomeMeta != null && nomeMeta.toString().isNotEmpty) {
          setState(() => _nome = nomeMeta.toString());
          final prefs2 = await SharedPreferences.getInstance();
          await prefs2.setString('driver_name', _nome);
        }
      }
    } catch (e) {
      // silenciar — manter fallback
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bom dia,';
    if (hour < 18) return 'Boa tarde,';
    return 'Boa noite,';
  }

  Future<void> _logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uuid = prefs.getString('driver_uuid') ?? '';
      final id = prefs.getInt('driver_id') ?? 0;
      final ts = DateTime.now().toUtc().toIso8601String();
      final payload = {
        'esta_online': false,
        'ultima_atualizacao': ts,
      };
      try {
        if (uuid.isNotEmpty) {
          await Supabase.instance.client.from('motoristas').update(payload).eq('uuid', uuid);
        } else if (id > 0) {
          await Supabase.instance.client.from('motoristas').update(payload).eq('id', id);
        }
      } catch (e) {
        debugPrint('Erro atualizando status do motorista: $e');
      }

      try {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        await Supabase.instance.client.auth.signOut();
      }

      try {
        await prefs.remove('driver_uuid');
        await prefs.remove('driver_name');
        await prefs.remove('driver_id');
      } catch (_) {}
    } catch (e) {
      debugPrint('Erro no logout: $e');
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.grey[900],
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.deepPurpleAccent,
                    child: const Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting(),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Olá, $_nome!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.person, color: Colors.white),
              title: const Text(
                'Perfil',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.of(context).pop(),
            ),
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Sair', style: TextStyle(color: Colors.red)),
              onTap: _logout,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
