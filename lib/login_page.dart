// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'register_page.dart';
import 'globals.dart';
// Removed direct import of main.dart to avoid circular imports; navigation uses named routes.

const String kLogoPath = 'assets/images/branco.jpg';

// Helper para login social (Google) — para Flutter Web use fluxo OAuth
Future<void> signInWithGoogleWeb(BuildContext context) async {
  try {
    // A API exata depende da versão do supabase_flutter; usamos signInWithOAuth quando disponível.
    final client = Supabase.instance.client;
    try {
      await client.auth.signInWithOAuth(OAuthProvider.google);
    } catch (e) {
      // fallback: tentar método genérico e logar instruções
      debugPrint('Google sign-in: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Erro ao iniciar login com Google (verifique configuração Web).',
          ),
        ),
      );
    }
  } catch (e) {
    debugPrint('Erro signInWithGoogleWeb: $e');
  }
}

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

  // removed unused wrapper for reset dialog; use `_mostrarModalEsqueciSenha()` directly

  Future<void> _login() async {
    // Início do método: ajuda a diagnosticar se o botão está conectado
    debugPrint('>>> ESTOU AQUI: _login');
    setState(() => _loading = true);
    try {
      // Forçar uso de credenciais fixas para teste (evita dependência dos campos de texto)
      const testEmail = 'lsouza557@gmail.com';
      const testPass = '555555';

      debugPrint('Iniciando tentativa de login com e-mail fixo para teste');

      // Tentar autenticação direta com Supabase
      try {
        await Supabase.instance.client.auth.signInWithPassword(
          email: testEmail,
          password: testPass,
        );
        debugPrint('Auth: signInWithPassword executado (sem exceção)');
      } catch (e) {
        debugPrint('Auth error (login): $e');
      }

      // Buscar motorista pelo e-mail fixo (Leandro tem user_id nulo)
      try {
        final motorista = await Supabase.instance.client
            .from('motoristas')
            .select()
            .eq('email', testEmail)
            .maybeSingle();

        if (motorista == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Motorista não encontrado para o e-mail de teste',
                ),
              ),
            );
          }
          return;
        }

        final Map<String, dynamic> record = Map<String, dynamic>.from(
          motorista,
        );
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

        // Extrair id (UUID ou int) e nome
        final dynamic rawId = record['id'];
        int recId = 0;
        String? recUuid;
        if (rawId is int) {
          recId = rawId;
        } else if (rawId is String) {
          final s = rawId.toString();
          if (s.contains('-')) {
            recUuid = s;
          } else {
            recId = int.tryParse(s) ?? 0;
          }
        }
        final nome = (record['nome'] ?? '').toString();

        // Persistir prefs
        final prefs = await SharedPreferences.getInstance();
        try {
          await prefs.setString('email_salvo', testEmail);
        } catch (_) {}
        await prefs.setBool('manter_logado', _keep);
        if (_rememberEmail) {
          await prefs.setString('email_salvo', testEmail);
        } else {
          await prefs.remove('email_salvo');
        }
        if (recUuid != null && recUuid.isNotEmpty) {
          await prefs.setString('driver_uuid', recUuid);
        }
        if (recId > 0) {
          await prefs.setInt('driver_id', recId);
          idLogado = recId;
        }
        await prefs.setString('driver_name', nome);
        nomeMotorista = nome;

        if (!mounted) {
          return;
        }
        Navigator.pushReplacementNamed(context, '/rota');
        return;
      } catch (e) {
        debugPrint('Erro durante busca/autenticação de teste: $e');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Erro: ${e.toString()}')));
        }
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
      final id = prefs.getInt('driver_id') ?? 0;
      if (savedKeep && id > 0) {
        if (!mounted) {
          return;
        }
          await Navigator.pushReplacementNamed(context, '/rota');
          if (!mounted) {
            return;
          }
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
                          // proteger contra null/paths inválidos
                          final path = kLogoPath;
                          await rootBundle.load(path);
                          return true;
                        } catch (_) {
                          return false;
                        }
                      }(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.done &&
                            snap.data == true) {
                          return Image.asset(
                            kLogoPath,
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

                  // Campos de input
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
                    child: TextButton(
                      onPressed: () => _mostrarModalEsqueciSenha(context),
                      child: const Text(
                        'Esqueci minha senha?',
                        style: TextStyle(color: Color(0xFF6750A4)),
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
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'E-mail cadastrado',
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
                            final email = emailCtl.text.trim();
                            if (email.isEmpty) {
                              if (!mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(contextSB).showSnackBar(
                                const SnackBar(
                                  content: Text('Preencha o e-mail'),
                                ),
                              );
                              return;
                            }

                            try {
                              final emailSafe = email;
                              if (emailSafe.isEmpty) {
                                if (!mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(contextSB).showSnackBar(
                                  const SnackBar(
                                    content: Text('E-mail inválido'),
                                  ),
                                );
                                return;
                              }

                              final dynamic resp = await client
                                  .from('motoristas')
                                  .select('id')
                                  .eq('email', emailSafe)
                                  .maybeSingle();

                              if (resp == null) {
                                if (!mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(contextSB).showSnackBar(
                                  const SnackBar(
                                    content: Text('E-mail não encontrado'),
                                  ),
                                );
                                return;
                              }

                              // avançar para etapa 2
                              try {
                                setStateSB(() => step = 2);
                              } catch (_) {}
                            } catch (e) {
                              try {
                                if (!mounted) {
                                  return;
                                }
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
                              if (!mounted) {
                                return;
                              }
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
                          obscureText: _obscureNova,
                          decoration: InputDecoration(
                            labelText: 'Nova senha',
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureNova
                                    ? Icons.visibility_off
                                    : Icons.visibility,
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
                          obscureText: _obscureConfirma,
                          decoration: InputDecoration(
                            labelText: 'Confirmar senha',
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirma
                                    ? Icons.visibility_off
                                    : Icons.visibility,
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
                              if (!mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(contextSB).showSnackBar(
                                const SnackBar(
                                  content: Text('Preencha ambas as senhas'),
                                ),
                              );
                              return;
                            }
                            if (s1 != s2) {
                              if (!mounted) {
                                return;
                              }
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
                                if (!mounted) {
                                  return;
                                }
                                // fechar o bottom sheet antes de qualquer diálogo
                                Navigator.of(ctx).pop();
                              } catch (_) {}

                              try {
                                if (!mounted) {
                                  return;
                                }
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
                                            if (!mounted) {
                                              return;
                                            }
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
                                if (!mounted) {
                                  return;
                                }
                                // após o diálogo, retornar à rota inicial
                                Navigator.of(
                                  parentContext,
                                ).popUntil((route) => route.isFirst);
                              } catch (_) {}
                            } catch (e) {
                              try {
                                if (!mounted) {
                                  return;
                                }
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
                            if (!mounted) {
                              return;
                            }
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
      // ensure keyboard hidden
      try {
        FocusScope.of(parentContext).unfocus();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 120));
    } catch (_) {}
  }
}
