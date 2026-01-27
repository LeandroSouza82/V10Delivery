import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nome = TextEditingController();
  final _sobrenome = TextEditingController();
  final _cpf = TextEditingController();
  final _telefone = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _senha2 = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _obscure2 = true;

  @override
  void dispose() {
    _nome.dispose();
    _sobrenome.dispose();
    _cpf.dispose();
    _telefone.dispose();
    _email.dispose();
    _senha.dispose();
    _senha2.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_senha.text != _senha2.text) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Senhas não coincidem')));
      return;
    }

    final emailValue = _email.text.trim();
    if (emailValue.isEmpty ||
        !emailValue.contains('@') ||
        !emailValue.contains('.com')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('E-mail inválido. Use um e-mail real com @ e .com'),
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: _email.text.trim(),
        password: _senha.text,
      );

      final user = res.user;
      if (user == null) throw 'Falha no cadastro';

      // insert into motoristas (inclui telefone)
      await Supabase.instance.client.from('motoristas').insert({
        'nome': _nome.text.trim(),
        'sobrenome': _sobrenome.text.trim(),
        'cpf': _cpf.text.trim(),
        'telefone': _telefone.text.trim(),
        'email': _email.text.trim(),
      });

      // Aviso: pedir confirmação por e-mail
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Quase lá!'),
            content: const Text(
              'Verifique seu e-mail para confirmar o cadastro antes de fazer o login.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  // Reenviar e-mail de confirmação — usamos o envio de magic link como forma de reenviar
                  try {
                    setState(() => _loading = true);
                    await Supabase.instance.client.auth.signInWithOtp(
                      email: emailValue,
                    );
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'E-mail de confirmação reenviado. Verifique sua caixa de entrada.',
                          ),
                        ),
                      );
                  } catch (e) {
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Erro ao reenviar e-mail: ${e.toString()}',
                          ),
                        ),
                      );
                  } finally {
                    if (mounted) setState(() => _loading = false);
                  }
                },
                child: const Text('Reenviar E-mail de Confirmação'),
              ),
            ],
          ),
        );
        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoginPage()),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _nome,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              TextField(
                controller: _sobrenome,
                decoration: const InputDecoration(labelText: 'Sobrenome'),
              ),
              TextField(
                controller: _cpf,
                decoration: const InputDecoration(labelText: 'CPF'),
              ),
              TextField(
                controller: _telefone,
                decoration: const InputDecoration(labelText: 'Telefone'),
              ),
              Image.asset(
                'assets/images/branco.jpg',
                height: 140,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'E-mail'),
              ),
              TextField(
                controller: _senha,
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
              TextField(
                controller: _senha2,
                obscureText: _obscure2,
                decoration: InputDecoration(
                  labelText: 'Confirmar senha',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure2 ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscure2 = !_obscure2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loading ? null : _register,
                child: _loading
                    ? const CircularProgressIndicator()
                    : const Text('Registrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
