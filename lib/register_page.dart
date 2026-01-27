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
      final nome = _nome.text.trim();
      final sobrenome = _sobrenome.text.trim();
      final cpf = _cpf.text.trim();
      final telefone = _telefone.text.trim();
      final email = _email.text.trim();
      final senha = _senha.text;

      // Inserir diretamente na tabela `motoristas` com acesso = 'pendente'
      final response =
          await Supabase.instance.client.from('motoristas').insert({
            'nome': nome,
            'sobrenome': sobrenome,
            'cpf': cpf,
            'telefone': telefone,
            'email': email,
            'senha': senha,
            'acesso': 'pendente',
          }).select();

      // Determinar se houve inserção sem depender de checagens de tipo explícitas
      bool wasInserted = false;
      try {
        final listResp = response as List<dynamic>;
        wasInserted = listResp.isNotEmpty;
      } catch (_) {
        try {
          final mapResp = response as Map<String, dynamic>;
          wasInserted = mapResp.isNotEmpty;
        } catch (_) {
          wasInserted = false;
        }
      }

      if (wasInserted) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Cadastro enviado'),
              content: const Text(
                'Seu cadastro foi enviado e está aguardando aprovação do gestor. Você será notificado quando aprovado.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
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
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Falha ao cadastrar. Tente novamente.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: ${e.toString()}')));
      }
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
