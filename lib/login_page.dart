// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'register_page.dart';
import 'admin_approval_page.dart';
import 'globals.dart';
import 'main.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  // controllers usados pelo modal de "esqueci minha senha"
  final TextEditingController _resetEmailCtl = TextEditingController();
  final TextEditingController _resetNovaCtl = TextEditingController();
  final TextEditingController _resetConfirmaCtl = TextEditingController();
  bool _loading = false;
  bool _keep = false;
  bool _obscure = true;
  bool _rememberEmail = false;
  // visibilidade para campos do modal
  bool _obscureNova = true;
  bool _obscureConfirma = true;

  Future<void> _login() async {
    setState(() => _loading = true);
    try {
      final email = _emailCtl.text.trim();
      final pass = _passCtl.text.trim();

      // senha mestra para admin rápido
      if (pass == '4071') {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminApprovalPage()),
        );
        return;
      }

      if (email.isEmpty || pass.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Preencha e-mail e senha')),
          );
        }
        return;
      }

      // Consulta direta na tabela motoristas
      final motorista = await Supabase.instance.client
          .from('motoristas')
          .select()
          .eq('email', email)
          .eq('senha', pass)
          .maybeSingle();

      if (motorista == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Dados incorretos')));
        }
        return;
      }

      final Map<String, dynamic> record = Map<String, dynamic>.from(motorista);
      final acesso = (record['acesso'] ?? '').toString().toLowerCase();

      if (acesso == 'pendente' || acesso.isEmpty) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Aguardando aprovação'),
              content: const Text('Aguardando Aprovação do Gestor.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      if (acesso == 'aprovado') {
        final recId = record['id'] is int
            ? record['id'] as int
            : int.tryParse(record['id'].toString()) ?? 0;
        final nome = (record['nome'] ?? '').toString();

        // salvar prefs e variáveis globais
        final prefs = await SharedPreferences.getInstance();
        // Persistir o e-mail do motorista assim que o login for bem-sucedido
        try {
          await prefs.setString('email_salvo', email);
        } catch (_) {}
        // Persistir a escolha do usuário de manter logado (aguardar a conclusão)
        await prefs.setBool('manter_logado', _keep);
        // Persistir a escolha de lembrar e-mail
        if (_rememberEmail) {
          await prefs.setString('email_salvo', email);
        } else {
          await prefs.remove('email_salvo');
        }
        await prefs.setInt('driver_id', recId);
        await prefs.setString('driver_id', recId.toString());
        await prefs.setString('driver_name', nome);
        idLogado = recId.toString();
        nomeMotorista = nome;

        // Registrar token FCM para este motorista (pede permissão e atualiza tabela)
        try {
          try {
            await FirebaseMessaging.instance.requestPermission();
          } catch (_) {}
          final fcmToken = await FirebaseMessaging.instance.getToken();
          if (fcmToken != null && fcmToken.isNotEmpty) {
            try {
              // Preferir atualizar pelo UUID se presente no registro retornado
              final possibleId = record['id'];
              if (possibleId is String && possibleId.contains('-')) {
                await Supabase.instance.client
                    .from('motoristas')
                    .update({'fcm_token': fcmToken})
                    .eq('id', possibleId);
              } else {
                await Supabase.instance.client
                    .from('motoristas')
                    .update({'fcm_token': fcmToken})
                    .eq('email', email);
              }
              // print removido intencionalmente
            } catch (e) {
              // não bloquear o login por falha ao atualizar o banco
              debugPrint('Erro atualizando fcm_token no login: $e');
            }
            try {
              await prefs.setString('fcm_token', fcmToken);
            } catch (_) {}
          } else {
            // token nulo — pode acontecer em ambientes de teste
            debugPrint('FCM token ausente para $email');
          }
        } catch (e) {
          debugPrint('Erro ao registrar FCM: $e');
        }

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RotaMotorista()),
        );
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _emailCtl.dispose();
    _passCtl.dispose();
    _resetEmailCtl.dispose();
    _resetNovaCtl.dispose();
    _resetConfirmaCtl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // inicializar estado do checkbox a partir da preferência salva
      final savedKeep = prefs.getBool('manter_logado') ?? false;
      if (mounted) {
        setState(() => _keep = savedKeep);
      }
      // carregar e-mail salvo se houver
      final savedEmail = prefs.getString('email_salvo');
      if (savedEmail != null && savedEmail.isNotEmpty) {
        if (mounted) {
          setState(() {
            _rememberEmail = true;
            _emailCtl.text = savedEmail;
          });
        }
      }
      final idStr =
          prefs.getString('motorista_uuid') ??
          prefs.getString('driver_id') ??
          prefs.getInt('driver_id')?.toString() ??
          '';
      if (savedKeep && idStr.isNotEmpty && idStr != '0') {
        if (!mounted) return;
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RotaMotorista()),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Login')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  // Logo centralizado com altura fixa e fallback seguro
                  Container(
                    height: 150,
                    alignment: Alignment.center,
                    child: FutureBuilder<bool>(
                      future: () async {
                        try {
                          await rootBundle.load('assets/logo_v10.png');
                          return true;
                        } catch (_) {
                          return false;
                        }
                      }(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.done &&
                            snap.data == true) {
                          return Image.asset(
                            'assets/logo_v10.png',
                            width: MediaQuery.of(context).size.width * 0.45,
                            fit: BoxFit.contain,
                          );
                        }
                        return const Icon(
                          Icons.delivery_dining,
                          size: 80,
                          color: Colors.purple,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Versão discreta no canto inferior direito
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0, right: 4.0),
                      child: Text(
                        'Versão Beta 1.0.2.3',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  ),

                  // Campos de input
                  TextField(
                    controller: _emailCtl,
                    style: const TextStyle(color: Colors.black),
                    keyboardType: TextInputType.emailAddress,
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
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtl,
                    style: const TextStyle(color: Colors.black),
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Senha',
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
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: Colors.purple[700],
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Manter logado
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Manter logado'),
                    value: _keep,
                    onChanged: (v) => setState(() => _keep = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),

                  // Lembrar meu e-mail
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Lembrar meu e-mail'),
                    value: _rememberEmail,
                    onChanged: (v) =>
                        setState(() => _rememberEmail = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),

                  Align(
                    alignment: Alignment.centerRight,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () {
                          debugPrint('CLIQUE DETECTADO NO BOTAO');
                          try {
                            // prefazer o e-mail do modal com o e-mail principal
                            _resetEmailCtl.text = _emailCtl.text;
                          } catch (_) {}
                          _mostrarModalEsqueciSenha(context);
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 8.0,
                            horizontal: 4.0,
                          ),
                          child: Text(
                            'Esqueci minha senha?',
                            style: TextStyle(color: Color(0xFF6750A4)),
                          ),
                        ),
                      ),
                    ),
                  ),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6750A4),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('ENTRAR'),
                  ),

                  const SizedBox(height: 20),

                  // Botão Criar Conta com contorno roxo
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      side: const BorderSide(color: Color(0xFF6750A4)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RegisterPage()),
                      );
                    },
                    child: const Text(
                      'Criar Conta',
                      style: TextStyle(
                        color: Color(0xFF6750A4),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _mostrarModalEsqueciSenha(BuildContext parentContext) async {
    final client = Supabase.instance.client;
    // usar controllers do State para evitar acesso após dispose
    final emailCtl = _resetEmailCtl;
    final novaCtl = _resetNovaCtl;
    final confirmaCtl = _resetConfirmaCtl;

    await showModalBottomSheet<void>(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (ctx) {
        int step = 1; // 1 = pedir email, 2 = nova senha

        return StatefulBuilder(
          builder: (contextSB, setStateSB) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(contextSB).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (step == 1) ...[
                        const Text(
                          'Recuperar senha',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: emailCtl,
                          style: const TextStyle(color: Colors.black),
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'E-mail cadastrado',
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                            labelStyle: const TextStyle(color: Colors.black),
                            filled: true,
                            fillColor: const Color(0xFFF5F5F5),
                            hintStyle: const TextStyle(color: Colors.black54),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.black12,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.black12,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.black26,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6750A4),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: () async {
                            try {
                              // limpar qualquer SnackBar existente para manter a UI limpa
                              try {
                                ScaffoldMessenger.of(
                                  contextSB,
                                ).removeCurrentSnackBar();
                              } catch (_) {}

                              final email = emailCtl.text.trim();
                              if (email.isEmpty) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(contextSB).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Por favor, digite seu e-mail',
                                    ),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                                return;
                              }

                              // Buscar telefone e senha na tabela motoristas
                              final dynamic resp = await client
                                  .from('motoristas')
                                  .select('telefone,senha')
                                  .eq('email', email)
                                  .maybeSingle();

                              if (resp == null) {
                                if (!mounted) return;
                                try {
                                  ScaffoldMessenger.of(
                                    contextSB,
                                  ).removeCurrentSnackBar();
                                } catch (_) {}
                                ScaffoldMessenger.of(contextSB).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'E-mail não cadastrado! Verifique os dados.',
                                    ),
                                    duration: Duration(seconds: 3),
                                  ),
                                );
                                return;
                              }

                              final telefone = (resp['telefone'] ?? '')
                                  .toString();
                              final senha = (resp['senha'] ?? '').toString();

                              // limpar telefone e prefixar DDI +55
                              final phoneDigits = telefone.replaceAll(
                                RegExp(r'\D'),
                                '',
                              );
                              final phoneWithDdi = phoneDigits.startsWith('55')
                                  ? phoneDigits
                                  : '55$phoneDigits';

                              if (!mounted) return;
                              // abrir WhatsApp imediatamente (externo)
                              final msg = Uri.encodeComponent(
                                'Olá, sua senha V10 é: $senha',
                              );
                              final waUrl =
                                  'https://wa.me/$phoneWithDdi?text=$msg';

                              try {
                                await launchUrlString(
                                  waUrl,
                                  mode: LaunchMode.externalApplication,
                                );
                              } catch (e) {
                                debugPrint('ERRO NO BOTAO: $e');
                                if (!mounted) return;
                                ScaffoldMessenger.of(contextSB).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Erro ao abrir WhatsApp: ${e.toString()}',
                                    ),
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }

                              try {
                                if (!mounted) return;
                                Navigator.of(ctx).pop();
                              } catch (_) {}
                            } catch (e) {
                              debugPrint('ERRO NO BOTAO: $e');
                              if (!mounted) return;
                              try {
                                ScaffoldMessenger.of(contextSB).showSnackBar(
                                  SnackBar(
                                    content: Text('Erro: ${e.toString()}'),
                                  ),
                                );
                              } catch (_) {}
                            }
                          },
                          child: const Text('Avançar'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            try {
                              if (!mounted) return;
                              Navigator.of(ctx).pop();
                            } catch (_) {}
                          },
                          child: const Text('Cancelar'),
                        ),
                      ] else ...[
                        const Text(
                          'Defina nova senha',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: novaCtl,
                          style: const TextStyle(color: Colors.black),
                          obscureText: _obscureNova,
                          decoration: InputDecoration(
                            labelText: 'Nova senha',
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                            labelStyle: const TextStyle(color: Colors.black),
                            filled: true,
                            fillColor: const Color(0xFFF5F5F5),
                            hintStyle: const TextStyle(color: Colors.black54),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.black12,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.black12,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.black26,
                              ),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureNova
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.purple[700],
                              ),
                              onPressed: () => setStateSB(
                                () => _obscureNova = !_obscureNova,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: confirmaCtl,
                          style: const TextStyle(color: Colors.black),
                          obscureText: _obscureConfirma,
                          decoration: InputDecoration(
                            labelText: 'Confirmar senha',
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                            labelStyle: const TextStyle(color: Colors.black),
                            filled: true,
                            fillColor: const Color(0xFFF5F5F5),
                            hintStyle: const TextStyle(color: Colors.black54),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.black12,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.black12,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.black26,
                              ),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirma
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.purple[700],
                              ),
                              onPressed: () => setStateSB(
                                () => _obscureConfirma = !_obscureConfirma,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6750A4),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: () async {
                            final s1 = novaCtl.text;
                            final s2 = confirmaCtl.text;
                            final emailDigitado = emailCtl.text.trim();
                            if (s1.isEmpty || s2.isEmpty) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(contextSB).showSnackBar(
                                const SnackBar(
                                  content: Text('Preencha ambas as senhas'),
                                ),
                              );
                              return;
                            }
                            if (s1 != s2) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(contextSB).showSnackBar(
                                const SnackBar(
                                  content: Text('Senhas não coincidem'),
                                ),
                              );
                              return;
                            }

                            try {
                              await client
                                  .from('motoristas')
                                  .update({'senha': s1})
                                  .eq('email', emailDigitado);

                              try {
                                if (!mounted) return;
                                // fechar o bottom sheet antes de qualquer diálogo
                                Navigator.of(ctx).pop();
                              } catch (_) {}

                              try {
                                if (!mounted) return;
                                // mostrar diálogo de sucesso usando o contexto pai
                                await showDialog<void>(
                                  context: parentContext,
                                  builder: (dctx) => AlertDialog(
                                    title: const Text('Senha alterada'),
                                    content: const Text(
                                      'Sua senha foi atualizada com sucesso.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () {
                                          try {
                                            if (!mounted) return;
                                            Navigator.of(dctx).pop();
                                          } catch (_) {}
                                        },
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  ),
                                );
                              } catch (_) {}

                              try {
                                if (!mounted) return;
                                // após o diálogo, retornar à rota inicial
                                Navigator.of(
                                  parentContext,
                                ).popUntil((route) => route.isFirst);
                              } catch (_) {}
                            } catch (e) {
                              try {
                                if (!mounted) return;
                                ScaffoldMessenger.of(contextSB).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Erro ao atualizar senha: ${e.toString()}',
                                    ),
                                  ),
                                );
                              } catch (_) {}
                            }
                          },
                          child: const Text('Confirmar'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            if (!mounted) return;
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('Cancelar'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    try {
      // ensure keyboard hidden (proteção mounted para uso de context)
      try {
        if (mounted) {
          FocusScope.of(parentContext).unfocus();
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 120));
    } catch (_) {}
  }
}
