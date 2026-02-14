import 'package:flutter/material.dart';
import 'package:v10_delivery/services/supabase_service.dart';
import 'package:v10_delivery/screens/login_screen.dart';

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
      // Salvar apenas dígitos no banco (remover máscara)
      final cpfRaw = _cpf.text.replaceAll(RegExp(r'\D'), '');
      final telefoneRaw = _telefone.text.replaceAll(RegExp(r'\D'), '');
      final email = _email.text.trim();
      final senha = _senha.text;

      // Inserir diretamente na tabela `motoristas` com acesso = 'pendente'
      final response = await SupabaseService.signUpMotorista(
        nome: nome,
        sobrenome: sobrenome,
        cpf: cpfRaw,
        telefone: telefoneRaw,
        email: email,
        senha: senha,
      );

      // Determinar se houve inserção
      bool wasInserted = false;
      if (response is List) {
        wasInserted = response.isNotEmpty;
      } else if (response is Map) {
        wasInserted = response.isNotEmpty;
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

          if (!mounted) {
            return;
          }
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  // Moto icon, centralizado, menor que no login
                  const Center(
                    child: Icon(
                      Icons.delivery_dining,
                      size: 60,
                      color: Colors.purple,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Campos ordenados e espaçados
                  TextField(
                    controller: _nome,
                    decoration: const InputDecoration(
                      labelText: 'Nome',
                      border: UnderlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _sobrenome,
                    decoration: const InputDecoration(
                      labelText: 'Sobrenome',
                      border: UnderlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _cpf,
                    decoration: const InputDecoration(
                      labelText: 'CPF',
                      border: UnderlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _telefone,
                    decoration: const InputDecoration(
                      labelText: 'Telefone',
                      border: UnderlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _email,
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      border: UnderlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _senha,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      border: const UnderlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _senha2,
                    obscureText: _obscure2,
                    decoration: InputDecoration(
                      labelText: 'Confirmar Senha',
                      border: const UnderlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure2 ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () => setState(() => _obscure2 = !_obscure2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _loading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Registrar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
