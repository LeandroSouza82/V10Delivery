import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'register_page.dart';
import 'home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  bool _loading = false;
  bool _keep = false;
  bool _obscure = true;

  Future<void> _showResetDialog() async {
    final emailCtl = TextEditingController();
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Recuperar senha'),
          content: TextField(
            controller: emailCtl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'E-mail'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Enviar'),
            ),
          ],
        ),
      );

      if (result == true) {
        final email = emailCtl.text.trim();
        await Supabase.instance.client.auth.resetPasswordForEmail(email);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Se este e-mail estiver cadastrado, um link de redefinição será enviado.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      emailCtl.dispose();
    }
  }

  Future<void> _login() async {
    setState(() => _loading = true);
    try {
      final email = _emailCtl.text.trim();
      final pass = _passCtl.text;
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: pass,
      );

      final user = res.user;
      if (user == null) {
        throw 'Falha ao autenticar. Verifique e-mail/senha. Se você não confirmou o e-mail, confirme antes de tentar novamente.';
      }

      final userEmail = user.email;
      if (userEmail == null) {
        await Supabase.instance.client.auth.signOut();
        throw 'E-mail do usuário não disponível';
      }

      // verify motorista exists
      final motorista = await Supabase.instance.client
          .from('motoristas')
          .select()
          .eq('email', userEmail)
          .maybeSingle();

      if (motorista == null) {
        await Supabase.instance.client.auth.signOut();
        throw 'E-mail não autorizado na tabela motoristas.';
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('keep_logged_in', _keep);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Image.asset(
              'assets/images/branco.jpg',
              height: 140,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Senha',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _showResetDialog,
                child: const Text('Esqueci minha senha'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: _keep,
                  onChanged: (v) => setState(() => _keep = v ?? false),
                ),
                const Text('Manter logado'),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _login,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('ENTRAR'),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RegisterPage()),
                );
              },
              child: const Text('Criar Conta'),
            ),
          ],
        ),
      ),
    );
  }
}
