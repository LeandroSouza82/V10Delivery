import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'globals.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart'; // ADD

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nome = TextEditingController();
  final _cpfController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _email = TextEditingController();
  final _senhaController = TextEditingController();
  final _senha2Controller = TextEditingController();
  bool _loading = false;

  // Formatadores de máscara
  final MaskTextInputFormatter cpfFormatter = MaskTextInputFormatter(
    mask: '###.###.###-##',
    filter: {"#": RegExp(r'[0-9]')},
  );

  final MaskTextInputFormatter telFormatter = MaskTextInputFormatter(
    mask: '(##) #####-####',
    filter: {"#": RegExp(r'[0-9]')},
  );

  // Visibilidade de senha
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;

  @override
  void dispose() {
    _nome.dispose();
    _cpfController.dispose();
    _telefoneController.dispose();
    _email.dispose();
    _senhaController.dispose();
    _senha2Controller.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (_senhaController.text != _senha2Controller.text) {
      if (!mounted) return;
      try {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senhas não coincidem')),
      );
      return;
    }

    final emailValue = _email.text.trim();
    if (emailValue.isEmpty || !emailValue.contains('@') || !emailValue.contains('.com')) {
      if (!mounted) return;
      try {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
      } catch (_) {}
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
      // Salvar apenas dígitos no banco (remover máscara)
      final cpfRaw = _cpfController.text.replaceAll(RegExp(r'\D'), '');
      final telefoneRaw = _telefoneController.text.replaceAll(
        RegExp(r'\D'),
        '',
      );
      final email = _email.text.trim();
      final senha = _senhaController.text;

      // Construir payload: enviar APENAS os campos solicitados
      final Map<String, dynamic> payload = {
        'nome': nome,
        'cpf': cpfRaw,
        'telefone': telefoneRaw,
        // garantir que novo cadastro venha bloqueado até aprovação
        'aprovado': false,
      };
      if (email.isNotEmpty) payload['email'] = email;
      if (senha.isNotEmpty) payload['senha'] = senha;

      final response = await Supabase.instance.client
          .from('motoristas')
          .insert(payload)
          .select();

      // Extrair id retornado pelo Supabase (aceita List ou Map)
      dynamic insertedRecord;
      try {
        try {
          // Tentar tratar como lista primeiro (caso comum do Supabase)
          final List<dynamic> listResp = response as List<dynamic>;
          if (listResp.isNotEmpty) insertedRecord = listResp.first;
        } catch (_) {
          // Se não for lista, tentar tratar como mapa
          try {
            final Map respMap = response as Map;
            if (respMap['data'] != null && respMap['data'] is List) {
              final List<dynamic> data = respMap['data'] as List<dynamic>;
              if (data.isNotEmpty) insertedRecord = data.first;
            } else {
              insertedRecord = respMap;
            }
          } catch (_) {
            insertedRecord = null;
          }
        }
      } catch (_) {
        insertedRecord = null;
      }

      if (insertedRecord != null) {
        final dynamic newId = insertedRecord['id'];
        final prefs = await SharedPreferences.getInstance();
        // Salvar nome para uso imediato
        await prefs.setString('driver_name', nome);

        // Se o id vier numérico (ou string numérica), salvar como driver_id
        final String newIdStr = newId?.toString() ?? '';
        final int? parsedId = int.tryParse(newIdStr);
        if (parsedId != null) {
          await prefs.setInt('driver_id', parsedId);
          await prefs.setString('driver_id', parsedId.toString());
          // armazenar id em memória como string (compatibilidade UUID)
          idLogado = newIdStr;
        } else if (newIdStr.isNotEmpty) {
          // Supabase retornou UUID: salvar em chaves de fallback consultadas pelo app
          await prefs.setString('motorista_uuid', newIdStr);
          await prefs.setString('supabase_user_id', newIdStr);
          idLogado = newIdStr;
        }

        // Persistir email/senha em prefs se fornecidos (opcional)
        if (email.isNotEmpty) await prefs.setString('email_salvo', email);

        // Mostrar modal informando que o cadastro foi realizado
        if (!mounted) {
          return;
        }
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Cadastro realizado!'),
            content: const Text(
              'Cadastro realizado! Aguarde a aprovação do gestor para acessar o sistema.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  try {
                    if (!mounted) {
                      return;
                    }
                    Navigator.of(ctx).pop();
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                    );
                  } catch (_) {}
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
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
      debugPrint('Erro ao registrar motorista: $e');
      final errStr = e.toString().toLowerCase();
      try {
        if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();
      } catch (_) {}
        if (mounted) {
          // detectar erro conhecido de coluna 'aprovado' ausente no schema
          if (errStr.contains('column "aprovado"') || (errStr.contains('aprovad') && errStr.contains('column'))) {
            debugPrint('Schema error detectado ao cadastrar motorista: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Erro de schema: coluna "aprovado" não encontrada no banco. Contate o desenvolvedor.'),
                backgroundColor: Colors.red,
              ),
            );
          } else if (errStr.contains('unique') || errStr.contains('duplicate') || errStr.contains('already')) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Este CPF ou E-mail já está cadastrado!'),
                backgroundColor: Colors.red,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erro ao salvar os dados: ${e.toString().split('\n').first}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // Campo CPF (substituir o existente)
  Widget _buildCpfField() {
    return TextFormField(
      controller: _cpfController,
      keyboardType: TextInputType.number,
      inputFormatters: [cpfFormatter],
      style: const TextStyle(color: Colors.black),
      decoration: const InputDecoration(
        labelText: 'CPF',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: TextStyle(color: Colors.black),
        filled: true,
        fillColor: Color(0xFFF5F5F5),
        border: OutlineInputBorder(),
        hintText: '000.000.000-00',
      ),
    );
  }

  // Campo Telefone (substituir o existente)
  Widget _buildTelefoneField() {
    return TextFormField(
      controller: _telefoneController,
      keyboardType: TextInputType.number,
      inputFormatters: [telFormatter],
      style: const TextStyle(color: Colors.black),
      decoration: const InputDecoration(
        labelText: 'Telefone',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: TextStyle(color: Colors.black),
        filled: true,
        fillColor: Color(0xFFF5F5F5),
        border: OutlineInputBorder(),
        hintText: '(00) 90000-0000',
      ),
    );
  }

  // Campo Senha (substituir o existente)
  Widget _buildPasswordField() {
    return TextFormField(
      controller: _senhaController,
      obscureText: !_passwordVisible,
      style: const TextStyle(color: Colors.black),
      decoration: InputDecoration(
        labelText: 'Senha',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: const TextStyle(color: Colors.black),
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(
            _passwordVisible ? Icons.visibility : Icons.visibility_off,
            color: Colors.purple[700] ?? Colors.deepPurple,
          ),
          onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
        ),
      ),
    );
  }

  // Campo Confirmar Senha (substituir o existente)
  Widget _buildConfirmPasswordField() {
    return TextFormField(
      controller: _senha2Controller,
      obscureText: !_confirmPasswordVisible,
      style: const TextStyle(color: Colors.black),
      decoration: InputDecoration(
        labelText: 'Confirmar Senha',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: const TextStyle(color: Colors.black),
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(
            _confirmPasswordVisible ? Icons.visibility : Icons.visibility_off,
            color: Colors.purple[700] ?? Colors.deepPurple,
          ),
          onPressed: () => setState(
            () => _confirmPasswordVisible = !_confirmPasswordVisible,
          ),
        ),
      ),
    );
  }

  // Botão Registrar (substituir estilo do botão existente)
  Widget _buildRegisterButton() {
    return ElevatedButton(
      onPressed: _loading ? null : _handleRegister,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.purple, // botão roxo
        foregroundColor: Colors.white, // texto branco
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: _loading
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text('Registrar', style: TextStyle(color: Colors.white)),
    );
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
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      labelText: 'Nome',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      labelStyle: const TextStyle(color: Colors.black),
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      hintStyle: const TextStyle(color: Colors.black54),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.black12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.black12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.black26),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildCpfField(),
                  const SizedBox(height: 16),
                  _buildTelefoneField(),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _email,
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      labelText: 'E-mail',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      labelStyle: const TextStyle(color: Colors.black),
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      hintStyle: const TextStyle(color: Colors.black54),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.black12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.black12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.black26),
                      ),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  _buildPasswordField(),
                  const SizedBox(height: 16),
                  _buildConfirmPasswordField(),
                  const SizedBox(height: 20),
                  _buildRegisterButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
