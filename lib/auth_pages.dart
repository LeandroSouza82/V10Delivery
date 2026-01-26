import 'package:flutter/material.dart';
import 'main.dart';
import 'globals.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:google_sign_in/google_sign_in.dart';

// Número do gestor para contato via WhatsApp (inclua 55 + DDD)
const String telefoneGestor = '5548996525008';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await Future.delayed(const Duration(seconds: 5));
    // Pequena espera adicional para fechamento de animações
    await Future.delayed(const Duration(milliseconds: 100));

    if (!mounted) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final nome = prefs.getString('driver_name');
      final telefone = prefs.getString('driver_phone');
      final telefoneLimpo = telefone?.replaceAll(RegExp(r'\D'), '') ?? '';
      final stay = prefs.getBool('stay_logged_in') ?? false;

      if (nome == null ||
          nome.isEmpty ||
          telefone == null ||
          telefone.isEmpty ||
          !stay) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
        return;
      }

      // Verificar rapidamente no Supabase se o acesso ainda é 'aprovado'
      final client = Supabase.instance.client;
      try {
        // DEBUG: mostrar o telefone limpo usado na verificação automática
        debugPrint(
          'DEBUG: Buscando no banco pelo telefone (Splash): $telefoneLimpo',
        );
        final List<dynamic> res = await client
            .from('motoristas')
            .select('id,acesso')
            .eq('telefone', telefoneLimpo)
            .limit(1);

        if (res.isEmpty) {
          // Registro não encontrado — limpar e voltar ao login
          try {
            await prefs.clear();
          } catch (_) {}
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginPage()),
          );
          return;
        }

        final acesso =
            (res.first as Map<String, dynamic>)['acesso']
                ?.toString()
                .toLowerCase() ??
            '';
        if (acesso == 'aprovado') {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const V10DeliveryApp()),
          );
          return;
        }

        // Caso acesso não seja aprovado (pendente/bloqueado), limpar e voltar ao login
        try {
          await prefs.clear();
        } catch (_) {}
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
        return;
      } catch (e) {
        // Em caso de erro de rede, ficar no login por segurança
        try {
          await prefs.clear();
        } catch (_) {}
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
        return;
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      body: Center(child: Image.asset('assets/images/preto.png', width: 220)),
    );
  }
}

// Tela administrativa simples para listar e aprovar motoristas pendentes
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final client = Supabase.instance.client;
  int _refreshKey = 0;

  Future<List<Map<String, dynamic>>> _fetchPendentes() async {
    try {
      final dynamic res = await client
          .from('motoristas')
          .select('id,nome,telefone,acesso')
          .eq('acesso', 'pendente')
          .order('id', ascending: false);
      return (res is List) ? List<Map<String, dynamic>>.from(res) : [];
    } catch (e) {
      debugPrint('ERRO ADMIN: $e');
      return [];
    }
  }

  Future<void> _aprovar(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar aprovação'),
        content: const Text('Deseja aprovar este motorista?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Não'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sim'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await client
          .from('motoristas')
          .update({'acesso': 'aprovado'})
          .eq('id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Motorista aprovado')));
      setState(() => _refreshKey++);
    } catch (e) {
      debugPrint('ERRO AO APROVAR: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Erro ao aprovar')));
    }
  }

  Future<void> _reprovar(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar bloqueio'),
        content: const Text('Deseja bloquear este motorista?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Não'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sim'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await client
          .from('motoristas')
          .update({'acesso': 'bloqueado'})
          .eq('id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Motorista bloqueado')));
      setState(() => _refreshKey++);
    } catch (e) {
      debugPrint('ERRO AO BLOQUEAR: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Erro ao bloquear')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin - Motoristas Pendentes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        key: ValueKey(_refreshKey),
        future: _fetchPendentes(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          final items = snap.data ?? [];
          if (items.isEmpty)
            return const Center(child: Text('Nenhum motorista pendente'));
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (context, i) {
              final m = items[i];
              return ListTile(
                title: Text(m['nome'] ?? '—'),
                subtitle: Text(m['telefone'] ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed: () => _aprovar(m['id'] as int),
                    ),
                    IconButton(
                      icon: const Icon(Icons.block, color: Colors.red),
                      onPressed: () => _reprovar(m['id'] as int),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _telController = TextEditingController();
  bool _manterLogado = false;
  bool _isLoading = false;
  final maskFormatter = MaskTextInputFormatter(
    mask: '(##) #####-####',
    filter: {"#": RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );

  @override
  void initState() {
    super.initState();
    // Resetar contador de cliques do WhatsApp quando o usuário digitar outro telefone
    _telController.addListener(() async {
      try {
        final raw = _telController.text.trim();
        final cleaned = raw.replaceAll(RegExp(r'\D'), '');
        final prefs = await SharedPreferences.getInstance();
        final last = prefs.getString('last_whatsapp_phone') ?? '';
        if (cleaned.isNotEmpty && cleaned != last) {
          await prefs.setInt('cliques_whatsapp', 0);
          await prefs.setString('last_whatsapp_phone', cleaned);
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _nomeController.dispose();
    try {
      _telController.removeListener(() {});
    } catch (_) {}
    _telController.dispose();
    super.dispose();
  }

  // helpers para contar cliques no WhatsApp (evitar spam)
  Future<int> _getWhatsAppClicks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('cliques_whatsapp') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _incrementWhatsAppClicks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt('cliques_whatsapp') ?? 0;
      await prefs.setInt('cliques_whatsapp', current + 1);
    } catch (_) {}
  }

  Future<void> _entrar() async {
    final nome = _nomeController.text.trim();
    final tel = _telController.text.trim();
    // Telefone sem máscara (apenas dígitos) para uso no banco
    final telLimpo = tel.replaceAll(RegExp(r'\D'), '');

    // Atalho secreto para AdminPage: digitar 9999 no campo telefone
    if (telLimpo == '9999') {
      if (!mounted) return;
      setState(() => _isLoading = false);
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const AdminPage()));
      return;
    }

    if (nome.isEmpty || tel.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, preencha todos os campos')),
      );
      return;
    }

    setState(() => _isLoading = true);

    Future<void> abrirWhatsApp(
      String nomeMotorista,
      String telefoneMotorista,
    ) async {
      final message =
          "Olá! Me chamo $nomeMotorista e gostaria de liberar meu acesso no V10 Delivery. Meu telefone é $telefoneMotorista.";
      final url =
          "https://wa.me/$telefoneGestor?text=${Uri.encodeComponent(message)}";
      final uri = Uri.parse(url);
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o WhatsApp')),
      );
    }

    try {
      final client = Supabase.instance.client;
      // DEBUG: mostrar o telefone sem máscara usado na busca
      debugPrint('DEBUG LOGIN: Buscando no banco por: $telLimpo');

      // CONSULTA: buscar motorista apenas pelo telefone (regra do requisito)
      final dynamic queryRes = await client
          .from('motoristas')
          .select('id,acesso,nome,telefone')
          .eq('telefone', telLimpo)
          .limit(1);
      final List<dynamic> res = queryRes is List ? queryRes : [];

      // CASO 1: NÃO EXISTE -> antes de inserir, verificar novamente por duplicatas
      if (res.isEmpty) {
        try {
          // Rechecar: preferir ordenar por created_at, mas usar id como fallback
          List<dynamic> existing = <dynamic>[];
          try {
            final dynamic recheck = await client
                .from('motoristas')
                .select('id,acesso,nome,created_at')
                .eq('telefone', telLimpo)
                .order('created_at', ascending: false)
                .limit(1);
            existing = recheck is List ? recheck : [];
          } catch (e) {
            debugPrint('DEBUG: created_at not available, fallback por id: $e');
            try {
              final dynamic recheck2 = await client
                  .from('motoristas')
                  .select('id,acesso,nome')
                  .eq('telefone', telLimpo)
                  .order('id', ascending: false)
                  .limit(1);
              existing = recheck2 is List ? recheck2 : [];
            } catch (e2) {
              debugPrint('ERRO NA RE-CHECAGEM (fallback): $e2');
            }
          }

          if (existing.isNotEmpty) {
            final existingMotorista = existing.first as Map<String, dynamic>;
            final existingAcesso = (existingMotorista['acesso'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final existingNome = (existingMotorista['nome'] ?? nome).toString();

            if (existingAcesso == 'pendente') {
              // Já existe um cadastro pendente: não inserir outro, apenas orientar o usuário
              try {
                final prefs = await SharedPreferences.getInstance();
                // limpar prefs do usuário anterior e usar exatamente os valores do registro existente no banco
                await prefs.clear();
                final existingPhone = (existingMotorista['telefone'] ?? '')
                    .toString()
                    .replaceAll(RegExp(r'\D'), '');
                await prefs.setString('driver_name', existingNome.trim());
                await prefs.setString('driver_phone', existingPhone);
                // salvar id do motorista
                final existingId = existingMotorista['id'] is int
                    ? existingMotorista['id'] as int
                    : int.tryParse(existingMotorista['id'].toString()) ?? 0;
                if (existingId > 0) {
                  await prefs.setInt('driver_id', existingId);
                  idLogado = existingId;
                } else {
                  await prefs.remove('driver_id');
                  idLogado = null;
                }
                // salvar avatar vindo do registro (se houver)
                final existingFoto =
                    (existingMotorista['foto_url'] ??
                            existingMotorista['foto'] ??
                            '')
                        .toString();
                if (existingFoto.isNotEmpty) {
                  await prefs.setString('avatar_path', existingFoto);
                } else {
                  await prefs.remove('avatar_path');
                }
                await prefs.setBool('stay_logged_in', false);
              } catch (_) {}

              final int clicks = await _getWhatsAppClicks();
              final bool blocked = clicks >= 2;
              if (!mounted) return;
              await showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                  title: const Text('Cadastro em Análise ⏳'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Olá $existingNome! Seu cadastro já está em análise e aguarda aprovação pelo gestor.',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Limite de 2 tentativas de contato',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      if (blocked) const SizedBox(height: 8),
                      if (blocked)
                        const Text(
                          'Você já solicitou aprovação. Por favor, aguarde o contato do gestor.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                    ],
                  ),
                  actions: [
                    ElevatedButton.icon(
                      style: blocked
                          ? ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey,
                            )
                          : ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF25D366),
                            ),
                      icon: const Icon(Icons.chat, color: Colors.white),
                      label: Text(
                        blocked
                            ? 'Aguarde o retorno do gestor'
                            : 'Confirmar no WhatsApp',
                        style: const TextStyle(color: Colors.white),
                      ),
                      onPressed: blocked
                          ? null
                          : () async {
                              await _incrementWhatsAppClicks();
                              abrirWhatsApp(existingNome.trim(), telLimpo);
                            },
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Fechar'),
                    ),
                  ],
                ),
              );
              return;
            }

            // Se existir e for aprovado, prosseguir como aprovado
            if (existingAcesso == 'aprovado') {
              try {
                final prefs = await SharedPreferences.getInstance();
                // limpar prefs do usuário anterior e salvar exatamente os valores do registro do banco
                await prefs.clear();
                final existingPhone = (existingMotorista['telefone'] ?? '')
                    .toString()
                    .replaceAll(RegExp(r'\D'), '');
                await prefs.setString('driver_name', existingNome.trim());
                await prefs.setString('driver_phone', existingPhone);
                final existingId = existingMotorista['id'] is int
                    ? existingMotorista['id'] as int
                    : int.tryParse(existingMotorista['id'].toString()) ?? 0;
                if (existingId > 0) {
                  await prefs.setInt('driver_id', existingId);
                  idLogado = existingId;
                } else {
                  await prefs.remove('driver_id');
                  idLogado = null;
                }
                final existingFoto =
                    (existingMotorista['foto_url'] ??
                            existingMotorista['foto'] ??
                            '')
                        .toString();
                if (existingFoto.isNotEmpty) {
                  await prefs.setString('avatar_path', existingFoto);
                } else {
                  await prefs.remove('avatar_path');
                }
                // atualizar nome global em memória
                nomeMotorista = existingNome.trim();
                if (_manterLogado) await prefs.setBool('stay_logged_in', true);
                debugPrint('DEBUG LOGIN: Entrando como ${existingNome.trim()}');
              } catch (_) {}

              if (!mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const V10DeliveryApp()),
              );
              return;
            }
          }

          // Continua sem registro: inserir como pendente
          try {
            debugPrint('DEBUG: Inserindo motorista com telefone: $telLimpo');
            await client.from('motoristas').insert({
              'nome': nome,
              'telefone': telLimpo,
              'acesso': 'pendente',
            });
          } catch (e) {
            debugPrint('ERRO AO INSERIR MOTORISTA: $e');
          }
        } catch (e) {
          debugPrint('ERRO NA RE-CHECAGEM DE DUPLICADOS: $e');
        }

        // Salvar no SharedPreferences a versão limpa do telefone para sincronizar com a Splash
        try {
          final prefs = await SharedPreferences.getInstance();
          // limpar prefs do usuário anterior and salvar os valores do novo registro pendente
          await prefs.clear();
          await prefs.setString('driver_name', nome.trim());
          await prefs.setString('driver_phone', telLimpo);
          await prefs.remove('avatar_path');
          await prefs.setBool('stay_logged_in', false);
          // sem id (ainda pendente/inserido), remover driver_id
          await prefs.remove('driver_id');
          idLogado = null;
          debugPrint('DEBUG LOGIN: Entrando como ${nome.trim()}');
        } catch (_) {}

        if (!mounted) return;
        final int clicks = await _getWhatsAppClicks();
        final bool blocked = clicks >= 2;
        if (!mounted) return;

        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Cadastro em Análise ⏳'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Olá ${nome.trim()}! Seu cadastro foi recebido, mas precisa ser aprovado pelo gestor.',
                ),
                const SizedBox(height: 12),
                Text(
                  'Limite de 2 tentativas de contato',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                if (blocked) const SizedBox(height: 8),
                if (blocked)
                  const Text(
                    'Você já solicitou aprovação. Por favor, aguarde o contato do gestor.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
              ],
            ),
            actions: [
              ElevatedButton.icon(
                style: blocked
                    ? ElevatedButton.styleFrom(backgroundColor: Colors.grey)
                    : ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                      ),
                icon: const Icon(Icons.chat, color: Colors.white),
                label: Text(
                  blocked
                      ? 'Aguarde o retorno do gestor'
                      : 'Confirmar no WhatsApp',
                  style: const TextStyle(color: Colors.white),
                ),
                onPressed: blocked
                    ? null
                    : () async {
                        await _incrementWhatsAppClicks();
                        abrirWhatsApp(nome.trim(), telLimpo);
                      },
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Fechar'),
              ),
            ],
          ),
        );
        return;
      }

      // CASO 2/3: Usuário encontrado no banco — sincronizar perfil e tomar ação conforme 'acesso'
      final motorista = res.first as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      final nomeDb = (motorista['nome'] ?? nome).toString().trim();
      final dbPhone = (motorista['telefone'] ?? '').toString().replaceAll(
        RegExp(r'\D'),
        '',
      );
      final dbFoto = (motorista['foto_url'] ?? motorista['foto'] ?? '')
          .toString();
      final dbId = motorista['id'] is int
          ? motorista['id'] as int
          : int.tryParse(motorista['id'].toString()) ?? 0;
      await prefs.setString('driver_name', nomeDb);
      await prefs.setString('driver_phone', dbPhone);
      if (dbFoto.isNotEmpty) {
        await prefs.setString('avatar_path', dbFoto);
      } else {
        await prefs.remove('avatar_path');
      }
      if (dbId > 0) {
        await prefs.setInt('driver_id', dbId);
        idLogado = dbId;
      } else {
        await prefs.remove('driver_id');
        idLogado = null;
      }
      debugPrint('Sincronizando Perfil: Novo usuário detectado - $nomeDb');
      if (mounted) setState(() => nomeMotorista = nomeDb);

      final acesso = (motorista['acesso'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (acesso == 'pendente') {
        // manter stay_logged_in false e mostrar diálogo de pendência
        await prefs.setBool('stay_logged_in', false);
        final int clicksPend = await _getWhatsAppClicks();
        final bool blockedPend = clicksPend >= 2;
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Cadastro em Análise ⏳'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Olá $nomeDb! Seu cadastro foi recebido, mas precisa ser aprovado pelo gestor.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Limite de 2 tentativas de contato',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (blockedPend) const SizedBox(height: 8),
                if (blockedPend)
                  const Text(
                    'Você já solicitou aprovação. Por favor, aguarde o contato do gestor.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
              ],
            ),
            actions: [
              ElevatedButton.icon(
                style: blockedPend
                    ? ElevatedButton.styleFrom(backgroundColor: Colors.grey)
                    : ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                      ),
                icon: const Icon(Icons.chat, color: Colors.white),
                label: Text(
                  blockedPend
                      ? 'Aguarde o retorno do gestor'
                      : 'Confirmar no WhatsApp',
                  style: const TextStyle(color: Colors.white),
                ),
                onPressed: blockedPend
                    ? null
                    : () async {
                        await _incrementWhatsAppClicks();
                        abrirWhatsApp(nomeDb, dbPhone);
                      },
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Fechar'),
              ),
            ],
          ),
        );
        return;
      }

      if (acesso == 'aprovado') {
        if (_manterLogado) await prefs.setBool('stay_logged_in', true);
        if (mounted) setState(() => nomeMotorista = nomeDb);
        debugPrint('Sincronizando Perfil: Novo usuário detectado - $nomeDb');
        try {
          await client
              .from('motoristas')
              .update({'status': 'online'})
              .eq('id', dbId);
        } catch (e) {
          debugPrint('ERRO AO ATUALIZAR STATUS: $e');
        }
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const V10DeliveryApp()),
        );
        return;
      }

      // Outros casos: acesso negado
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Acesso não permitido.')));
      return;
    } catch (e) {
      debugPrint('ERRO NO LOGIN: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Erro ao verificar acesso. Tente novamente mais tarde.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Sign in com Google: busca por email em 'motoristas' e sincroniza driver_id
  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final google = GoogleSignIn(
        scopes: ['email', 'openid', 'profile'],
        // Use o Client ID de WEB como serverClientId para gerar o token aceito pelo Supabase
        serverClientId: '987623319824-g9drvf59efc18m89tddvueoqjm4md7r4.apps.googleusercontent.com',
        // NOTA: removido o campo `clientId` de Android aqui intencionalmente.
      );
      final account = await google.signIn();
      if (account == null) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Login Google cancelado')),
          );
        return;
      }
      final email = account.email;
      if (email.isEmpty) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Não foi possível obter o e-mail do Google'),
            ),
          );
        return;
      }

      final client = Supabase.instance.client;
      try {
        // Tentar localizar motorista pelo e-mail
        final dynamic q = await client
            .from('motoristas')
            .select('id,nome,telefone,acesso,foto_url')
            .eq('email', email)
            .limit(1);
        final Map<String, dynamic>? motorista = (q is List && q.isNotEmpty)
            ? Map<String, dynamic>.from(q.first)
            : null;

        if (motorista == null) {
          // E-mail não cadastrado: inserir registro pendente antes de solicitar via WhatsApp
          final nomeAuto = account.displayName?.trim().isNotEmpty == true
              ? account.displayName!.trim()
              : email.split('@').first;
          int novoId = 0;
          try {
            final dynamic insertRes = await client
                .from('motoristas')
                .insert({
                  'nome': nomeAuto,
                  'email': email,
                  'acesso': 'pendente',
                })
                .select('id');
            if (insertRes is List && insertRes.isNotEmpty) {
              final inserted = Map<String, dynamic>.from(insertRes.first);
              novoId = inserted['id'] is int
                  ? inserted['id'] as int
                  : int.tryParse(inserted['id'].toString()) ?? 0;
            }
          } catch (eInsert) {
            debugPrint('ERRO AO INSERIR PENDENTE: $eInsert');
          }

          // Atualizar prefs com dados mínimos e sem permitir entrar
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.clear();
            await prefs.setString('driver_name', nomeAuto);
            await prefs.setString('driver_phone', '');
            if (novoId > 0) {
              await prefs.setInt('driver_id', novoId);
              idLogado = novoId;
            } else {
              await prefs.remove('driver_id');
              idLogado = null;
            }
            await prefs.setBool('stay_logged_in', false);
          } catch (_) {}

          if (!mounted) return;
          // Mostrar diálogo com opção de solicitar cadastro via WhatsApp
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('E-mail não cadastrado'),
              content: Text(
                'Seu e-mail $email não está cadastrado no sistema. Deseja solicitar cadastro ao gestor via WhatsApp?',
              ),
              actions: [
                ElevatedButton(
                  onPressed: () async {
                    // Abrir WhatsApp com mensagem automática
                    final message =
                        'Olá, meu e-mail é $email e quero solicitar meu cadastro no V10 Delivery.';
                    final url =
                        'https://wa.me/$telefoneGestor?text=${Uri.encodeComponent(message)}';
                    final uri = Uri.parse(url);
                    final nav = Navigator.of(ctx);
                    try {
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    } catch (_) {}
                    nav.pop();
                  },
                  child: const Text('Solicitar Cadastro via WhatsApp'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Fechar'),
                ),
              ],
            ),
          );
          return;
        }

        // Usuário encontrado: sincronizar preferências e proceder conforme 'acesso'
        final acesso = (motorista['acesso'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final nomeDb = (motorista['nome'] ?? '').toString().trim();
        final telefoneDb = (motorista['telefone'] ?? '').toString().replaceAll(
          RegExp(r'\D'),
          '',
        );
        final fotoDb = (motorista['foto_url'] ?? motorista['foto'] ?? '')
            .toString();
        final id = motorista['id'] is int
            ? motorista['id'] as int
            : int.tryParse(motorista['id'].toString()) ?? 0;

        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        if (nomeDb.isNotEmpty) await prefs.setString('driver_name', nomeDb);
        if (telefoneDb.isNotEmpty)
          await prefs.setString('driver_phone', telefoneDb);
        if (fotoDb.isNotEmpty) await prefs.setString('avatar_path', fotoDb);
        if (id > 0) {
          await prefs.setInt('driver_id', id);
          idLogado = id;
        } else {
          await prefs.remove('driver_id');
          idLogado = null;
        }

        if (acesso == 'aprovado') {
          if (mounted) {
            nomeMotorista = nomeDb;
            setState(() {});
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const V10DeliveryApp()),
            );
          }
          return;
        } else if (acesso == 'pendente') {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cadastro em análise. Aguarde aprovação.'),
              ),
            );
          return;
        } else {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Acesso não permitido')),
            );
          return;
        }
      } catch (e) {
        debugPrint('ERRO GOOGLE -> SUPABASE: $e');
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erro ao verificar usuário no sistema'),
            ),
          );
        return;
      }
    } catch (e, st) {
      debugPrint('ERRO SIGNIN GOOGLE: ${e.runtimeType} - $e');
      debugPrint('STACK: $st');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro no login com Google: ${e.toString()}')),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _sair() {
    try {
      SystemNavigator.pop();
    } catch (_) {
      // fallback
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    Image.asset('assets/images/preto.png', height: 120),
                    const SizedBox(height: 40),
                    TextField(
                      controller: _nomeController,
                      decoration: const InputDecoration(
                        labelText: 'Nome do Motorista',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: _telController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [maskFormatter],
                      decoration: const InputDecoration(
                        labelText: 'Telefone',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _manterLogado,
                          onChanged: (v) =>
                              setState(() => _manterLogado = v ?? false),
                        ),
                        const SizedBox(width: 4),
                        const Text('Manter-se logado'),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D47A1),
                        minimumSize: const Size(double.infinity, 55),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _isLoading
                          ? null
                          : () async => await _entrar(),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'ENTRAR',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 55),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Colors.grey),
                        ),
                      ),
                      icon: const Icon(Icons.g_mobiledata, color: Colors.black),
                      label: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Entrar com Google',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                              ),
                            ),
                      onPressed: _isLoading
                          ? null
                          : () async => await _signInWithGoogle(),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 12),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Confirmar'),
                        content: const Text(
                          'Deseja realmente fechar o aplicativo?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Não'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Sim'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      _sair();
                    }
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                  ),
                  child: const Text('Sair do App'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
