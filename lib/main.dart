import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:intl/intl.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:retry/retry.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'location_service.dart';

import 'services/cache_service.dart';
import 'widgets/avisos_modal.dart';
// import 'package:v10_delivery/auth_pages.dart'; // removido: arquivo não existe no workspace
import 'globals.dart';
import 'login_page.dart';

// Número do gestor (formato internacional sem +).
// Nota: agora carregamos dinamicamente em tempo de execução a partir da tabela `configuracoes`.
const String prefSelectedMapKey = 'selected_map_app';

// Supabase configuration - keep hardcoded and trimmed
const String supabaseUrl = 'https://uqxoadxqcwidxqsfayem.supabase.co';
const String supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxeG9hZHhxY3dpZHhxc2ZheWVtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg0NDUxODksImV4cCI6MjA4NDAyMTE4OX0.q9_RqSx4YfJxlblPS9fwrocx3HDH91ff1zJvPbVGI8w';

// Modo offline para testes locais. Quando true, carrega dados de exemplo.
bool modoOffline = true;

// Modelo simples para histórico de entregas
class ItemHistorico {
  final String nomeCliente;
  final String horario;
  final String status;
  final String? motivo;
  final String? caminhoFoto;
  final String? caminhoAssinatura;

  ItemHistorico({
    required this.nomeCliente,
    required this.horario,
    required this.status,
    this.motivo,
    this.caminhoFoto,
    this.caminhoAssinatura,
  });
}

// Histórico global de entregas finalizadas
final List<ItemHistorico> historicoEntregas = [];
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase removed: não inicializar Firebase aqui.
  // Forçar orientação apenas em vertical (portrait)
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Tornar a status bar totalmente transparente e ajustar brilho dos ícones
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  // CONFIGURAÇÃO OFICIAL - NÃO ALTERAR
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey.trim());

  // Para teste: buscar dados do motorista pelo UUID de teste (substitui o uso
  // de id numérico durante desenvolvimento). Em produção o `driverId` real
  // deve vir do foreground storage pelo processo de login.
  const String testDriverUuid = '00c21342-1d55-4feb-bb5a-0045f9fdd095';
  try {
    final prefs = await SharedPreferences.getInstance();
    try {
      final client = Supabase.instance.client;

      List<dynamic> res = [];
      try {
        final dynamic q = await client
            .from('motoristas')
            .select('id,nome,avatar_path,telefone')
            .eq('id', testDriverUuid)
            .limit(1);
        debugPrint('Supabase query (uuid test) raw: $q');
        if (q is List) {
          res = q;
        } else if (q is Map && q['data'] != null) {
          res = q['data'] as List<dynamic>;
        }
      } catch (err) {
        debugPrint('Erro Supabase (uuid try): $err');
      }

      debugPrint('Resultado da Query: $res');

      if (res.isNotEmpty) {
        final record = res.first as Map<String, dynamic>;
        final dbName = (record['nome'] ?? '').toString();
        final dbAvatar = (record['avatar_path'] ?? '').toString();
        final recUuid = (record['id'] ?? '').toString();

        await prefs.setString('driver_uuid', recUuid);

        if (dbName.isNotEmpty) {
          await prefs.setString('driver_name', dbName);
          nomeMotorista = dbName;
        } else {
          await prefs.setString('driver_name', 'Motorista');
          nomeMotorista = 'Motorista';
        }

        if (dbAvatar.isNotEmpty) {
          await prefs.setString('avatar_path', dbAvatar);
        }
      } else {
        // Nenhum registro: gravar UUID de teste nas prefs para desenvolvimento
        await prefs.setString('driver_uuid', testDriverUuid);
        await prefs.setString('driver_name', 'Motorista');
        nomeMotorista = 'Motorista';
      }
    } catch (e) {
      debugPrint('Erro Supabase: $e');
      // Falha na consulta: gravar UUID de teste localmente
      await prefs.setString('driver_uuid', testDriverUuid);
      await prefs.setString('driver_name', 'Motorista');
      nomeMotorista = 'Motorista';
    }
  } catch (_) {}

  runApp(const MyApp());
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_DeliveryTaskHandler());
}

class _DeliveryTaskHandler extends TaskHandler {
  int _count = 0;
  bool _isPolling = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Inicialização do handler
    _count = 0;
    // Garantir que o Supabase esteja inicializado dentro do isolate do foreground task
    try {
      // Tentar acessar o client; se não inicializado isso pode lançar
      final _ = Supabase.instance.client;
      debugPrint('Supabase já inicializado no isolate');
    } catch (_) {
      try {
        await Supabase.initialize(
          url: supabaseUrl,
          anonKey: supabaseAnonKey.trim(),
        );
        debugPrint('Supabase inicializado no isolate do foreground task');
      } catch (e) {
        debugPrint('Falha ao inicializar Supabase no isolate: $e');
      }
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    _count++;
    try {
      final String? uuidReal = await FlutterForegroundTask.getData<String>(
        key: 'driverId',
      );
      if (uuidReal == null || uuidReal == '0' || uuidReal.isEmpty) {
        return;
      }

      // Evitar reentrância: se já estiver em polling, pular esta execução
      if (_isPolling) {
        return;
      }
      _isPolling = true;
      try {
        // Tentar buscar entregas para o motorista usando o UUID recuperado
        // Ordenar por `ordem_logistica` ascendente para garantir sequência correta
        final response = await Supabase.instance.client
            .from('entregas')
            .select('*')
            .eq('motorista_id', uuidReal)
            .or('status.eq.aguardando,status.eq.pendente')
            .order('ordem_logistica', ascending: true);

        final List<dynamic> lista = (response is List) ? response : <dynamic>[];
        debugPrint('📦 Entregas encontradas: ${lista.length}');

        FlutterForegroundTask.sendDataToMain({
          'entregas': lista,
          'driverId': uuidReal,
          'timestamp': DateTime.now().toIso8601String(),
        });
        try {
          // Também salvar em storage para que a UI possa recuperar caso a ponte esteja interrompida
          await FlutterForegroundTask.saveData(
            key: 'entregas',
            value: jsonEncode(lista),
          );
        } catch (e) {
          debugPrint('Erro ao salvar entregas no foreground storage: $e');
        }
      } catch (e) {
        debugPrint('BG: falha ao buscar entregas no supabase: $e');
      } finally {
        _isPolling = false;
      }
    } catch (e) {
      debugPrint('Erro ao obter driverId no foreground storage: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationPressed() {}
}

class V10DeliveryApp extends StatelessWidget {
  const V10DeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
      ),
      themeMode: ThemeMode.light,
      // Inicializa a partir da Splash para respeitar "Manter logado"
      home: const SplashPage(),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const V10DeliveryApp();
  }
}

// SplashPage: mostra logo centralizado por 5 segundos e navega
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    // Carregar nome do motorista salvo nas prefs para evitar persistência incorreta
    _loadSavedName();
    _start();
    _loadSavedName();
    _start();
  }

  Future<void> _loadSavedName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('driver_name') ?? '';
      if (saved.isNotEmpty) {
        nomeMotorista = saved;
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('Erro ao carregar driver_name nas prefs: $e');
    }
  }

  Future<void> _start() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final telefone = prefs.getString('driver_phone');
      // Limpar máscara do telefone antes de consultar o banco
      final telLimpo = telefone?.replaceAll(RegExp(r'\D'), '') ?? '';

      // Aguarda 5 segundos mostrando splash
      await Future.delayed(const Duration(seconds: 5));

      if (!mounted) return;

      // Respeitar a preferência de 'manter_logado' do usuário
      final keep = prefs.getBool('manter_logado') ?? false;
      final savedId = prefs.getInt('driver_id') ?? 0;
      if (keep && savedId > 0) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RotaMotorista()),
        );
        return;
      }

      // Se há telefone salvo, tentar checar o status no Supabase.
      if (telefone != null && telefone.isNotEmpty) {
        // Verificar no Supabase se o acesso ainda é aprovado
        try {
          final client = Supabase.instance.client;
          debugPrint('DEBUG SPLASH: Buscando por $telLimpo');
          // Tentar usar created_at para pegar o registro mais recente; se a coluna
          // não existir (schema alternativo), fazer fallback por id desc.
          List<dynamic> res = <dynamic>[];
          try {
            final dynamic q = await client
                .from('motoristas')
                .select('nome,acesso,created_at')
                .eq('telefone', telLimpo)
                .order('created_at', ascending: false)
                .limit(1);
            res = q is List ? q : [];
          } catch (e) {
            debugPrint(
              'DEBUG SPLASH: created_at não disponível, fallback por id: $e',
            );
            try {
              final dynamic q2 = await client
                  .from('motoristas')
                  .select('nome,acesso,id')
                  .eq('telefone', telLimpo)
                  .order('id', ascending: false)
                  .limit(1);
              res = q2 is List ? q2 : [];
            } catch (e2) {
              debugPrint('DEBUG SPLASH: Erro na query fallback: $e2');
            }
          }

          if (res.isNotEmpty) {
            final record = res.first as Map<String, dynamic>;
            final dbAcesso = (record['acesso'] ?? '').toString().toLowerCase();
            final dbNome = (record['nome'] ?? '').toString();
            debugPrint(
              'DEBUG SPLASH: Status no banco: ${record['acesso']} nome: $dbNome',
            );

            // Atualizar preferências locais com o nome vindo do DB
            try {
              final prefsUpdate = await SharedPreferences.getInstance();
              if (dbNome.isNotEmpty) {
                await prefsUpdate.setString('driver_name', dbNome);
                // atualizar nome em memória
                nomeMotorista = dbNome;
                // salvar id do motorista
                final recId = record['id'] is int
                    ? record['id'] as int
                    : int.tryParse(record['id'].toString()) ?? 0;
                if (recId > 0) {
                  await prefsUpdate.setInt('driver_id', recId);
                  idLogado = recId;
                }
              }
            } catch (e) {
              debugPrint('DEBUG SPLASH: Erro ao atualizar nome nas prefs: $e');
            }

            if (dbAcesso == 'aprovado') {
              if (!mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const RotaMotorista()),
              );
              return;
            }
          } else {
            debugPrint(
              'DEBUG SPLASH: Nenhum registro encontrado para $telLimpo',
            );
          }
        } catch (e) {
          debugPrint('DEBUG SPLASH: Erro ao consultar Supabase: $e');
          // erro na verificação: seguir para login por segurança
        }
        // Se não aprovado ou erro, limpar prefs e ir para login
        try {
          try {
            try {
              await prefs.setBool('manter_logado', false);
            } catch (_) {}
          } catch (_) {}
          try {
            await prefs.remove('driver_id');
            await prefs.remove('driver_name');
            await prefs.remove('avatar_path');
          } catch (_) {}
          idLogado = null;
        } catch (_) {}
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => LoginPage()));
        return;
      } else {
        // Sem telefone salvo: ir para login
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => LoginPage()));
        return;
      }
    } catch (e) {
      // fallback: ir para login
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => LoginPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 1200),
                      curve: Curves.easeInOutCubic,
                      builder: (context, value, child) {
                        final scale = 0.7 + (0.3 * value);
                        return Opacity(
                          opacity: value,
                          child: Transform.scale(
                            scale: scale,
                            child: SizedBox(
                              width: MediaQuery.of(context).size.width * 0.75,
                              child: Image.asset(
                                'assets/images/branco.jpg',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 30),
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF6750A4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                'Logística Inteligente',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w300,
                  letterSpacing: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _enviarWhatsApp(String mensagem, {String? phone}) async {
  // Construir Uri com `Uri` para garantir codificação correta
  Uri uri;
  if (phone != null && phone.isNotEmpty) {
    uri = Uri.https('api.whatsapp.com', '/send', {
      'phone': phone,
      'text': mensagem,
    });
  } else {
    uri = Uri.https('api.whatsapp.com', '/send', {'text': mensagem});
  }

  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
  } catch (_) {}

  // fallback para esquema nativo do WhatsApp
  try {
    Uri whatsapp;
    if (phone != null && phone.isNotEmpty) {
      whatsapp = Uri(
        scheme: 'whatsapp',
        host: 'send',
        queryParameters: {'phone': phone, 'text': mensagem},
      );
    } else {
      whatsapp = Uri(
        scheme: 'whatsapp',
        host: 'send',
        queryParameters: {'text': mensagem},
      );
    }
    if (await canLaunchUrl(whatsapp)) {
      await launchUrl(whatsapp, mode: LaunchMode.externalApplication);
    }
  } catch (_) {}
}

class RotaMotorista extends StatefulWidget {
  const RotaMotorista({super.key});

  @override
  RotaMotoristaState createState() => RotaMotoristaState();
}

class RotaMotoristaState extends State<RotaMotorista>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // Key global para o Scaffold para reduzir risco de perda de contexto
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _avatarPath;
  // Número do gestor, default para compatibilidade local — atualizado dinamicamente em carregarDados().
  String numeroGestor = '5548996525008';
  // ID do motorista carregado nas prefs — inicializado como 0 por segurança
  int _driverId = 0;
  // ID do motorista vindo do Supabase (UUID string). Inicializa como '0' até
  // termos certeza do user logado. Usado para updates no Supabase que esperam UUID.
  String _motoristaId = '0';
  // Código curto de fallback adicionado recentemente na tabela `motoristas`
  int? _codigoV10;

  // Geolocation: subscription para rastreamento em tempo real
  StreamSubscription<Position>? _positionSubscription;
  // Timer para checar storage do foreground task e repassar dados para UI
  Timer? _fgStorageTimer;
  String? _lastEntregasJson;

  // Solicita permissão de localização e inicia o stream de posições
  Future<void> _requestPermissionAndStartTracking() async {
    try {
      final LocationPermission permission =
          await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        // Mostrar alerta amigável se permissão negada
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Permissão de Localização'),
            content: const Text(
              'O aplicativo precisa da sua localização para funcionar corretamente. Por favor, ative o GPS nas configurações.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      // Iniciar stream de posições com alta precisão
      final settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );

      // Cancelar subscription anterior se existir
      try {
        await _positionSubscription?.cancel();
      } catch (_) {}

      _positionSubscription =
          Geolocator.getPositionStream(locationSettings: settings).listen(
            (Position pos) async {
              try {
                final motoristaId = _motoristaId ?? '0';
                // Proteção: evita enviar '0' ou vazio para o Supabase (evita 22P02)
                if (motoristaId == '0' || motoristaId.isEmpty) return;

                await Supabase.instance.client
                    .from('motoristas')
                    .update({
                      'lat': pos.latitude,
                      'lng': pos.longitude,
                      'ultima_atualizacao': DateTime.now().toIso8601String(),
                    })
                    .eq('id', motoristaId);
              } catch (e) {
                debugPrint('Erro ao atualizar localização no Supabase: $e');
              }
            },
            onError: (err) {
              debugPrint('Erro stream geolocalização: $err');
            },
          );
    } catch (e) {
      debugPrint('Erro ao iniciar rastreamento: $e');
    }
  }

  // Helper seguro: tenta iniciar o LocationService com o userId fornecido.
  // Nota: se você tiver uma classe `LocationService` no projeto, descomente
  // a chamada interna e remova o body vazio abaixo. Mantemos isto para
  // não introduzir referências inexistentes que quebrem a build.
  void _tryStartLocationServiceFor(String userId) {
    if (userId != '0' && userId.isNotEmpty) {
      try {
        LocationService().iniciarRastreio(userId);
      } catch (e) {
        debugPrint('Erro ao iniciar LocationService: $e');
      }
      return;
    }

    // Se o userId ainda for '0', tentar repetidamente por um tempo limitado
    const int maxAttempts = 15;
    const Duration delayBetween = Duration(seconds: 2);
    int attempts = 0;

    () async {
      while (attempts < maxAttempts) {
        await Future.delayed(delayBetween);
        attempts++;
        try {
          final supaId = Supabase.instance.client.auth.currentUser?.id;
          debugPrint(
            'DEBUG: Supabase currentSession: ${Supabase.instance.client.auth.currentSession}',
          );
          String found = supaId ?? '';
          if (found.isEmpty) {
            final prefs = await SharedPreferences.getInstance();
            found =
                prefs.getString('supabase_user_id') ??
                prefs.getString('user_id') ??
                prefs.getString('motorista_uuid') ??
                prefs.getString('driver_uuid') ??
                prefs.getInt('driver_id')?.toString() ??
                '';
            // Se ainda vazio e temos um _driverId numérico, tentar buscar na tabela
            if ((found.isEmpty || found == '0') && _driverId != 0) {
              try {
                final client = Supabase.instance.client;
                dynamic q = [];
                // Tentar buscar por id inteiro
                try {
                  final dynamic r = await client
                      .from('motoristas')
                      .select('id')
                      .eq('id', _driverId)
                      .limit(1);
                  debugPrint('DEBUG: Query motoristas by int raw: $r');
                  if (r is List) {
                    q = r;
                  } else if (r is Map && r['data'] != null) {
                    q = r['data'] as List<dynamic>;
                  }
                } catch (err) {
                  debugPrint('DEBUG: Erro query motoristas (int): $err');
                }
                // Se não achou, tentar por campo alternativa como motorista_id/string
                if ((q as List).isEmpty) {
                  try {
                    final dynamic r2 = await client
                        .from('motoristas')
                        .select('id')
                        .eq('motorista_id', _driverId.toString())
                        .limit(1);
                    debugPrint(
                      'DEBUG: Query motoristas by motorista_id raw: $r2',
                    );
                    if (r2 is List) {
                      q = r2;
                    } else if (r2 is Map && r2['data'] != null) {
                      q = r2['data'] as List<dynamic>;
                    }
                  } catch (err2) {
                    debugPrint(
                      'DEBUG: Erro query motoristas (motorista_id): $err2',
                    );
                  }
                }
                if ((q as List).isNotEmpty) {
                  final record = (q as List).first as Map<String, dynamic>;
                  final candidate = (record['id'] ?? '').toString();
                  if (candidate.isNotEmpty) found = candidate;
                }
              } catch (e) {
                debugPrint(
                  'DEBUG: Erro buscando UUID na tabela motoristas: $e',
                );
              }
            }
          }
          if (found.isNotEmpty && found != '0') {
            _motoristaId = found;
            try {
              LocationService().iniciarRastreio(found);
              debugPrint(
                'LocationService: iniciado após $attempts tentativas (UUID: $found)',
              );
            } catch (e) {
              debugPrint('Erro ao iniciar LocationService após retry: $e');
            }
            return;
          }
        } catch (e) {
          debugPrint('Erro no loop de tentativa do UUID: $e');
        }
      }
      debugPrint(
        'ID Supabase não encontrado após $maxAttempts tentativas; rastreio não iniciado.',
      );
    }();
  }

  // Busca em cascata a identidade real do motorista.
  // Retorna um mapa com 'id' (UUID string) e 'codigo_v10' (int) quando encontrado.
  // Tentativas: 1) supabase.auth.currentUser?.id 2) lookup por email 3) lookup por driver_id nas prefs/tabela
  Future<Map<String, dynamic>?> buscarIdentidadeReal() async {
    try {
      print('>>> ESTOU AQUI: buscarIdentidadeReal');
      debugPrint('DEBUG: iniciar buscarIdentidadeReal()');
      // Limpar identificação anterior para evitar troca de identidade ao trocar de conta
      _motoristaId = '0';
      _codigoV10 = null;
      String? email = Supabase.instance.client.auth.currentUser?.email?.trim();
      // Para testes rápidos em dispositivo, usar e-mail fixo se não houver sessão
      if (email == null || email.isEmpty) {
        email = 'lsouza557@gmail.com';
        debugPrint('DEBUG: usando e-mail fixo de teste: $email');
      }
      bool recoveredFromCache = false;
      if (email == null || email.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString('email_salvo');
        if (cached != null && cached.isNotEmpty) {
          email = cached.trim();
          recoveredFromCache = true;
        }
      }
      debugPrint(
        '🔍 DEBUG: Buscando no banco o UUID para o e-mail: ${email ?? 'NULL'}${recoveredFromCache ? ' (recuperado do cache)' : ''}',
      );
      // Se não há sessão atual e não conseguimos recuperar um e-mail, forçar fluxo de login
      final currentUser = Supabase.instance.client.auth.currentUser;
      if ((currentUser == null || currentUser.id == null) &&
          (email == null || email.isEmpty)) {
        debugPrint(
          '⚠️ Nenhuma sessão ativa e e-mail desconhecido — redirecionando para Login.',
        );
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
          );
        }
        return null;
      }
      // Tentativa principal: usar o e-mail da sessão atual (ou cache) para buscar o motorista
      try {
        if (email != null && email.isNotEmpty) {
          final client = Supabase.instance.client;
          try {
            // Usar .single() para obter exatamente um registro (evita necessidade de mapear list)
            final dynamic byEmail = await client
                .from('motoristas')
                .select()
                .eq('email', email)
                .single();

            if (byEmail != null) {
              final record = Map<String, dynamic>.from(byEmail as Map);
              final candidate = (record['id'] ?? '').toString();
              final codigo = record['codigo_v10'] is int
                  ? record['codigo_v10'] as int
                  : int.tryParse((record['codigo_v10'] ?? '').toString());
              final nomeBanco = (record['nome'] ?? '').toString();

              debugPrint(
                '🔍 Motorista encontrado via e-mail: $nomeBanco (id: $candidate)',
              );

              // Se o campo user_id na tabela estiver nulo ou vazio, atualizá-lo com o UID do Auth
              try {
                final currentUser = Supabase.instance.client.auth.currentUser;
                if (currentUser != null && currentUser.id != null) {
                  final userIdValue = record['user_id'];
                  if (userIdValue == null || userIdValue.toString().isEmpty) {
                    try {
                      await client
                          .from('motoristas')
                          .update({'user_id': currentUser.id})
                          .eq('id', candidate);
                      debugPrint(
                        '✅ Atualizado user_id do motorista $candidate para ${currentUser.id}',
                      );
                    } catch (e) {
                      debugPrint('Falha ao atualizar user_id: $e');
                    }
                  }
                }
              } catch (e) {
                debugPrint('Erro ao tentar atualizar vínculo user_id: $e');
              }

              if (candidate.isNotEmpty) {
                return {
                  'id': candidate,
                  'codigo_v10': codigo,
                  'nome': nomeBanco,
                };
              }
            }
          } catch (e) {
            debugPrint('DEBUG: busca por email (single) falhou: $e');
          }
        } else {
          debugPrint(
            'DEBUG: email do Supabase nulo ou vazio; pulando busca por email.',
          );
        }
      } catch (e) {
        debugPrint('DEBUG: busca por email falhou: $e');
      }

      // Tentativa 3: usar driver_id das prefs e consultar a tabela para recuperar UUID
      try {
        final prefs = await SharedPreferences.getInstance();
        final int? prefDriver = prefs.getInt('driver_id');
        if (prefDriver != null && prefDriver != 0) {
          final client = Supabase.instance.client;
          List<dynamic> res = [];
          try {
            final dynamic q = await client
                .from('motoristas')
                .select('id')
                .eq('id', prefDriver)
                .limit(1);
            debugPrint('DEBUG: query motoristas by int raw: $q');
            if (q is List) {
              res = q;
            } else if (q is Map && q['data'] != null) {
              res = q['data'] as List<dynamic>;
            }
          } catch (err) {
            debugPrint('DEBUG: erro query motoristas by int: $err');
          }
          if (res.isEmpty) {
            try {
              final dynamic q2 = await client
                  .from('motoristas')
                  .select('id')
                  .eq('motorista_id', prefDriver.toString())
                  .limit(1);
              debugPrint('DEBUG: query motoristas by motorista_id raw: $q2');
              if (q2 is List) {
                res = q2;
              } else if (q2 is Map && q2['data'] != null) {
                res = q2['data'] as List<dynamic>;
              }
            } catch (err2) {
              debugPrint('DEBUG: erro query motoristas by motorista_id: $err2');
            }
          }
          if (res.isNotEmpty) {
            final record = res.first as Map<String, dynamic>;
            final candidate = (record['id'] ?? '').toString();
            final codigo = record['codigo_v10'] is int
                ? record['codigo_v10'] as int
                : int.tryParse((record['codigo_v10'] ?? '').toString());
            final nomeBanco = (record['nome'] ?? '').toString();
            debugPrint('🔍 Logado como: $nomeBanco');
            if (candidate.isNotEmpty)
              return {'id': candidate, 'codigo_v10': codigo, 'nome': nomeBanco};
          }
        }
      } catch (e) {
        debugPrint('DEBUG: erro consultando prefs/tabla para UUID: $e');
      }
    } catch (e) {
      debugPrint('DEBUG: buscarIdentidadeReal falhou: $e');
    }
    return null;
  }

  Future<void> _pickAndSaveAvatar(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? img = await picker.pickImage(
        source: source,
        imageQuality: 25,
        maxWidth: 800,
      );
      if (img != null) {
        setState(() => _avatarPath = img.path);
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('avatar_path', img.path);
        } catch (_) {}
      }
    } catch (_) {}
  }

  // Recebe dados vindos do foreground task (ou do fallback de storage)
  void _onReceiveTaskData(Object data) {
    try {
      if (data is Map && data['entregas'] != null) {
        final dynamic raw = data['entregas'];
        List<dynamic> parsed = [];
        if (raw is String) {
          parsed = jsonDecode(raw) as List<dynamic>;
        } else if (raw is List) {
          parsed = raw;
        }
        // Atualizar lista local sem forçar conversões de tipos
        setState(() {
          entregas = List<dynamic>.from(
            parsed.map((e) => e as Map<String, dynamic>),
          );
        });
        _notifyEntregasDebounced(entregas);
      }
    } catch (e) {
      debugPrint('Erro em _onReceiveTaskData: $e');
    }
  }

  void _showAvatarPickerOptions() {
    final Color bg = modoDia ? Colors.white : Colors.grey[900]!;
    final Color textColor = modoDia ? Colors.black : Colors.white;

    showModalBottomSheet(
      context: context,
      backgroundColor: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt, color: textColor),
                title: Text(
                  'Tirar Foto (Câmera)',
                  style: TextStyle(color: textColor),
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _pickAndSaveAvatar(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: textColor),
                title: Text(
                  'Escolher da Galeria',
                  style: TextStyle(color: textColor),
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _pickAndSaveAvatar(ImageSource.gallery);
                },
              ),
              SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  String? caminhoFotoSession;
  XFile? fotoEvidencia;
  late AnimationController _buscarController;
  late Animation<double> _buscarOpacity;
  bool modoDia = false;
  int _esquemaCores = 0; // 0 = padrão, 1/2/3 = esquemas
  // Avisos do gestor: funções para buscar, marcar e atualizar badge
  Future<List<Map<String, dynamic>>> _buscarAvisos() async {
    try {
      final res = await Supabase.instance.client
          .from('avisos_gestor')
          .select('id,titulo,mensagem,created_at,lida')
          .eq('lida', false)
          .order('created_at', ascending: false);

      final list = res as List<dynamic>? ?? <dynamic>[];
      return list
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      debugPrint('Erro ao buscar avisos: $e');
    }
    return <Map<String, dynamic>>[];
  }

  Future<void> _atualizarAvisosNaoLidas() async {
    try {
      final res = await Supabase.instance.client
          .from('avisos_gestor')
          .select('id')
          .eq('lida', false);
      final list = res as List<dynamic>? ?? <dynamic>[];
      final int count = list.length;
      if (!mounted) return;
      setState(() {
        mensagensNaoLidas = count;
      });
    } catch (e) {
      debugPrint('Erro ao atualizar badge de avisos: $e');
    }
  }
  // Busca e reconexão

  Timer? _reconnectTimer;
  // Stream-based delivery list to reduce UI rebuild pressure
  final StreamController<List<dynamic>> _entregasController =
      StreamController<List<dynamic>>.broadcast();
  Timer? _entregasDebounce;
  Timer? _cacheDebounce;
  // histórico de itens finalizados (usar historicoEntregas global)
  // Índices dos cards que estão sendo pressionados (efeito visual)
  final Set<int> _pressedIndices = {};

  // Áudio: usar única instância para evitar consumo excessivo de memória
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _awaitStartChama = false; // usado para iniciar loop após som final
  // Estado ONLINE/OFFLINE do motorista
  bool _isOnline = false;

  // Lista inicial vazia — será preenchida por `carregarDados()`
  List<dynamic> entregas = [];
  // Lista local de avisos (cache curto) — limpa quando houver eventos Realtime
  final List<Map<String, dynamic>> _avisosLocal = <Map<String, dynamic>>[];
  // Subscription Realtime para avisos_gestor (guardamos para cancelar)
  dynamic _avisosSubscription;
  // Polling fallback para entregas quando Realtime não funcionar
  // Inicializar com 0 para que um novo registro com id=1 seja detectado
  // ignore: unused_field
  int _lastEntregaId = 0;
  // Controle para evitar tocar som no primeiro carregamento
  int _totalEntregasAntigo = -1;
  // Indica se já houve ao menos um carregamento bem-sucedido (para permitir tocar som)
  bool _hasInitialSync = false;
  // Indicador visual do polling: pisca a cada verificação; fica vermelho se offline
  // ignore: prefer_final_fields
  bool _pollingBlink = false;
  // ignore: prefer_final_fields
  bool _pollingOffline = false;
  // Controller para rolar a lista de entregas quando novos pedidos chegarem
  late ScrollController _entregasScrollController;
  Timer? _entregasPollingTimer;
  // alias getter para compatibilidade com instruções que usam `_entregas`
  List<dynamic> get _entregas => entregas;
  // CONTROLE DO MODAL DE SUCESSO (OK)
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _aptController = TextEditingController();

  final List<String> _opcoesEntrega = [
    'PRÓPRIO',
    'OUTROS',
    'ZELADOR',
    'SÍNDICO',
    'PORTEIRO',
    'FAXINEIRA',
    'MORADOR',
    'LOCKER',
    'CORREIO',
  ];

  // Caminho da foto de falha (usado pelo modal de FALHA)
  String? imagemFalha;
  // Motivo selecionado para falha (guardado no estado para reset/inspeção)
  String? motivoFalhaSelecionada;
  // Contadores dinâmicos (iniciados com 0 por segurança de null-safety)
  int entregasFaltam = 0;
  int recolhasFaltam = 0;
  int outrosFaltam = 0;
  // Novos totais solicitados
  int totalEntregas = 0;
  int totalRecolhas = 0;
  int totalOutros = 0;
  // Contador de mensagens não lidas (usado pelo badge no appBar)
  int mensagensNaoLidas = 0;
  String? _selectedMapName;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    // Solicitar permissão de localização o mais cedo possível
    Future.microtask(() async {
      try {
        await _requestPermissionAndStartTracking();
      } catch (_) {}
    });

    // Inicializar serviço de foreground (permissões serão solicitadas)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!kIsWeb) {
        try {
          // Checar permissão de notificações (Android 13+)
          final NotificationPermission permission =
              await FlutterForegroundTask.checkNotificationPermission();
          if (permission != NotificationPermission.granted) {
            await FlutterForegroundTask.requestNotificationPermission();
          }

          if (Platform.isAndroid) {
            if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
              // Requer permission android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
              await FlutterForegroundTask.requestIgnoreBatteryOptimization();
            }
          }

          // Inicializar opções do foreground task
          FlutterForegroundTask.init(
            androidNotificationOptions: AndroidNotificationOptions(
              channelId: 'v10_delivery_fg',
              channelName: 'v10_delivery Service',
              channelDescription:
                  'Serviço em primeiro plano para manter polling ativo',
              channelImportance: NotificationChannelImportance.LOW,
              priority: NotificationPriority.LOW,
              onlyAlertOnce: true,
            ),
            iosNotificationOptions: const IOSNotificationOptions(
              showNotification: false,
              playSound: false,
            ),
            foregroundTaskOptions: ForegroundTaskOptions(
              eventAction: ForegroundTaskEventAction.repeat(10000),
              autoRunOnBoot: false,
              autoRunOnMyPackageReplaced: true,
              allowWakeLock: true,
              allowWifiLock: true,
            ),
          );
          // Firebase removed: não registrar listener de token FCM.
          // localização já foi solicitada anteriormente (evita duplicação)
        } catch (e) {
          debugPrint('Erro init foreground task: $e');
        }
      } else {
        debugPrint('Web: pulando inicialização do FlutterForegroundTask');
      }
    });
    // iniciar cache service (não bloqueante)
    CacheService().init().catchError((e) => debugPrint('Cache init error: $e'));
    // Manter a tela acesa enquanto o app estiver em primeiro plano
    try {
      WakelockPlus.enable();
    } catch (_) {}
    super.initState();
    // Carregar driver_id das SharedPreferences o quanto antes (não-bloqueante)
    SharedPreferences.getInstance().then((prefs) async {
      try {
        _driverId = prefs.getInt('driver_id') ?? 0;
        // Tentar obter UUID do Supabase (aguardando caso ainda não tenha inicializado)
        debugPrint('DEBUG: Tentando pegar UUID do Supabase...');
        try {
          final supaId = Supabase.instance.client.auth.currentUser?.id;
          if (supaId != null && supaId.isNotEmpty) {
            _motoristaId = supaId;
          } else {
            // Fallback: tentar buscar de várias keys nas SharedPreferences
            final fromPrefs =
                prefs.getString('supabase_user_id') ??
                prefs.getString('user_id') ??
                prefs.getString('motorista_uuid') ??
                prefs.getString('driver_uuid') ??
                prefs.getInt('driver_id')?.toString();
            _motoristaId = (fromPrefs != null && fromPrefs.isNotEmpty)
                ? fromPrefs
                : '0';
          }
        } catch (e) {
          debugPrint('DEBUG: Erro obtendo UUID Supabase: $e');
          _motoristaId =
              prefs.getString('supabase_user_id') ??
              prefs.getString('user_id') ??
              prefs.getInt('driver_id')?.toString() ??
              '0';
        }
        // Restaurar estado online salvo
        _isOnline = prefs.getBool('is_online') ?? false;
      } catch (_) {
        _driverId = 0;
      }
      // Buscar identidade real em cascata e iniciar LocationService somente se houver ID válido
      try {
        final Map<String, dynamic>? foundMap = await buscarIdentidadeReal();
        if (foundMap != null && (foundMap['id'] ?? '').toString().isNotEmpty) {
          final String foundId = (foundMap['id'] ?? '').toString();
          _motoristaId = foundId;
          _codigoV10 = foundMap['codigo_v10'] is int
              ? (foundMap['codigo_v10'] as int)
              : int.tryParse((foundMap['codigo_v10'] ?? '').toString());
          debugPrint(
            '🚀 Motorista identificado! UUID: $_motoristaId | Código Curto: ${_codigoV10 ?? 'N/A'}',
          );
          try {
            LocationService().iniciarRastreio(_motoristaId);
            debugPrint(
              '✅ GPS: Rastreio iniciado para o motorista $_motoristaId',
            );
          } catch (e) {
            debugPrint('Erro iniciando LocationService: $e');
          }
          // Firebase removed: não buscar/registrar token FCM no auto-login.
        }
      } catch (e) {
        debugPrint('Erro ao buscar identidade real: $e');
      }

      debugPrint(
        '🚀 App iniciado - Driver ID: $_driverId, Supabase user: $_motoristaId',
      );
      // Tenta iniciar o serviço de localização (se implementado no projeto)
      try {
        _tryStartLocationServiceFor(_motoristaId);
      } catch (_) {}
      try {
        await _atualizarTokenNoBanco();
      } catch (e) {
        debugPrint('ERRO atualizarTokenNoBanco: $e');
      }
      // Se estava online antes, iniciar service e polling
      if (_isOnline) {
        try {
          await _startForegroundService();
        } catch (_) {}
        _startPolling();
      }
      // Garantir que o banco reflita o estado salvo
      try {
        await _atualizarStatusNoSupabase(_isOnline);
      } catch (e) {
        debugPrint('Erro sincronizando status no init: $e');
      }
    });
    // Garantir cache limpo e lista inicial vazia (teste: DB reiniciado com id=1)
    CacheService()
        .saveEntregas(<Map<String, dynamic>>[])
        .then((_) {
          if (!mounted) return;
          setState(() {
            entregas = [];
            _lastEntregaId = 0;
          });
        })
        .catchError((e) {
          debugPrint('Erro limpando cache local antes do run: $e');
        });

    // Chamar carregarDados() primeiro para popular a lista vinda do Supabase
    carregarDados();
    // Calcular contadores iniciais (será atualizado após carregarDados)
    _atualizarContadores();
    // Atualizar badge de avisos não lidos ao iniciar o app
    _atualizarAvisosNaoLidas();
    // Se Realtime não estiver diretamente disponível via cliente, usar polling
    // curto para garantir atualização imediata do badge quando o DB mudar.
    try {
      _avisosSubscription = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted) return;
        _avisosLocal.clear();
        _atualizarAvisosNaoLidas();
      });
    } catch (e) {
      debugPrint('Erro ao iniciar polling de avisos_gestor: $e');
    }

    // Inicializar controller de rolagem e (opcionalmente) polling via _startPolling
    try {
      _entregasScrollController = ScrollController();
    } catch (e) {
      debugPrint('Erro iniciando ScrollController: $e');
    }

    // animação de procura de rotas (opacidade pulsante)
    _buscarController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    )..repeat(reverse: true);
    _buscarOpacity = Tween(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _buscarController, curve: Curves.easeInOut),
    );

    // quando um som terminar, se sinalizado, iniciar o loop do 'chama.mp3'
    _audioPlayer.onPlayerComplete.listen((event) {
      if (_awaitStartChama) {
        _awaitStartChama = false;
        // inicia loop de chamada se for o caso
        _startChamaLoop();
      }
    });

    // Garantir configurações iniciais do player
    try {
      _audioPlayer.setReleaseMode(ReleaseMode.stop);
      _audioPlayer.setVolume(1.0);
    } catch (_) {}

    // Carregar preferência de app de mapa salvo
    SharedPreferences.getInstance().then((prefs) {
      final mapName = prefs.getString(prefSelectedMapKey);
      if (mapName != null && mapName.isNotEmpty) {
        setState(() => _selectedMapName = mapName);
      }
      // Carregar avatar salvo (se houver)
      final av = prefs.getString('avatar_path');
      if (av != null && av.isNotEmpty) {
        setState(() => _avatarPath = av);
      }
      // Carregar nome salvo (garante sincronização imediata da UI após login)
      final savedName = prefs.getString('driver_name');
      if (savedName != null && savedName.isNotEmpty) {
        setState(() => nomeMotorista = savedName);
      }
    });

    // Carregar preferência de esquema de cores (modo_cores). Default = 1
    SharedPreferences.getInstance().then((prefs) {
      final modo = prefs.getInt('modo_cores');
      if (modo != null) {
        setState(() => _esquemaCores = modo);
      } else {
        setState(() => _esquemaCores = 1);
      }
    });
    // Carregar preferência de modo offline (default true)
    SharedPreferences.getInstance().then((prefs) {
      final mo = prefs.getBool('modo_offline');
      if (mo != null) {
        setState(() => modoOffline = mo);
      } else {
        setState(() => modoOffline = true);
      }
    });
    // DEBUG: abrir Drawer automaticamente se a flag estiver setada nas prefs
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final open = prefs.getBool('debug_open_drawer') ?? false;
        if (open) {
          try {
            if (!mounted) return;
            // ignore: use_build_context_synchronously
            Scaffold.of(context).openEndDrawer();
          } catch (_) {}
          await prefs.remove('debug_open_drawer');
        }
      } catch (_) {}
    });
    // (debug) flag temporária removida — não setamos mais prefs automaticamente
    // Carregar dados iniciais do Supabase (chamado acima após inicialização)
    // Carregar dados iniciais do Supabase (chamado acima após inicialização)
    // Busca removida: não inicializar listener
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Não cancelamos timers ao pausar; apenas registramos o estado para debug.
    debugPrint('AppLifecycleState changed: $state');
  }

  @override
  void dispose() {
    // Restaurar comportamento padrão de tela ao sair
    try {
      WakelockPlus.disable();
    } catch (_) {}
    // Cancelar polling/subscription de avisos (se houver)
    try {
      if (_avisosSubscription is Timer) {
        (_avisosSubscription as Timer).cancel();
      }
    } catch (_) {}
    try {
      if (_entregasPollingTimer != null) {
        _entregasPollingTimer?.cancel();
      }
    } catch (_) {}
    _buscarController.dispose();
    _audioPlayer.dispose();
    try {
      _entregasScrollController.dispose();
    } catch (_) {}
    _nomeController.dispose();
    _aptController.dispose();

    _reconnectTimer?.cancel();
    _entregasDebounce?.cancel();
    _cacheDebounce?.cancel();
    _entregasController.close();
    try {
      _fgStorageTimer?.cancel();
    } catch (_) {}
    try {
      _positionSubscription?.cancel();
    } catch (_) {}
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _startForegroundService() async {
    try {
      if (kIsWeb) {
        debugPrint('Web: pulando startForegroundService');
        return;
      }
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.restartService();
        return;
      }
      try {
        if (_motoristaId != '0' && _motoristaId.isNotEmpty) {
          await FlutterForegroundTask.saveData(
            key: 'driverId',
            value: _motoristaId,
          );
          debugPrint('driverId salvo no foreground storage');
        }
      } catch (e) {
        debugPrint('Erro ao salvar driverId no foreground storage: $e');
      }
      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'v10_delivery — Online',
        notificationText: 'Serviço ativo para manter atualizações',
        notificationIcon: null,
        notificationButtons: [
          const NotificationButton(id: 'stop', text: 'Parar'),
        ],
        callback: startCallback,
      );
      debugPrint('Foreground service iniciado');
    } catch (e) {
      debugPrint('Erro ao iniciar foreground service: $e');
    }
  }

  Future<void> _stopForegroundService() async {
    try {
      if (kIsWeb) {
        debugPrint('Web: pulando stopForegroundService');
        return;
      }
      await FlutterForegroundTask.stopService();
      debugPrint('Foreground service parado');
    } catch (e) {
      debugPrint('Erro ao parar foreground service: $e');
    }
  }

  // Atualiza a lista de entregas de forma centralizada e notifica o stream
  void _setEntregas(List<dynamic> nova) {
    if (!mounted) return;
    // Se não conhecemos o motorista (nem numeric nem UUID), não aceitar listas vindas do servidor
    // — em vez disso garantir que a UI mostre 0 pedidos.
    if (_driverId == 0 && (_motoristaId == '0' || _motoristaId.isEmpty)) {
      setState(() => entregas = []);
      try {
        if (!_entregasController.isClosed) _entregasController.add(entregas);
      } catch (_) {}
      _notifyEntregasDebounced(entregas);
      return;
    }

    setState(() => entregas = nova);
    _notifyEntregasDebounced(nova);
  }

  // Inicia o polling de entregas (10s)
  void _startPolling() {
    try {
      if (kIsWeb) {
        debugPrint('Web: pulando startPolling (usar fallback web)');
        return;
      }
      _entregasPollingTimer?.cancel();
      _entregasPollingTimer = Timer.periodic(const Duration(seconds: 10), (
        timer,
      ) async {
        try {
          // Ler driverId diretamente do storage do foreground task (fonte da verdade)
          final String? storedId = await FlutterForegroundTask.getData<String>(
            key: 'driverId',
          );
          // silenciosamente não faz nada se não houver id válido
          if (storedId == null || storedId == '0' || storedId.isEmpty) return;

          debugPrint('🔄 POLLING AUTOMÁTICO EXECUTANDO');
          debugPrint('   └─ Timestamp: ${DateTime.now()}');
          debugPrint('   └─ Driver ID (storage): $storedId');

          // Forçar carregar dados usando o UUID recuperado
          await carregarDados();
        } catch (e) {
          debugPrint('❌ Erro no polling entregas: $e');
        }
      });
      debugPrint('Polling iniciado');
    } catch (e) {
      debugPrint('Erro ao iniciar polling de entregas: $e');
    }
  }

  // Para o polling de entregas
  void _stopPolling() {
    try {
      _entregasPollingTimer?.cancel();
      _entregasPollingTimer = null;
      debugPrint('Polling parado');
    } catch (e) {
      debugPrint('Erro ao parar polling: $e');
    }
  }

  void _notifyEntregasDebounced(List<dynamic> nova) {
    // Debounce rapid updates to avoid render pressure and BLASTBufferQueue overload
    _entregasDebounce?.cancel();
    _entregasDebounce = Timer(const Duration(milliseconds: 200), () {
      if (_entregasController.isClosed) return;
      try {
        _entregasController.add(nova);
      } catch (_) {}
    });
    // Sempre acionar também a gravação em cache debounced
    try {
      final listaMap = nova
          .map<Map<String, String>>((e) => Map<String, String>.from(e as Map))
          .toList();
      _saveToCacheDebounced(listaMap);
    } catch (_) {}
  }

  void _saveToCacheDebounced(List<Map<String, String>> lista) {
    // Debounce cache writes to reduce I/O pressure
    _cacheDebounce?.cancel();
    _cacheDebounce = Timer(const Duration(seconds: 1), () async {
      try {
        // convert to dynamic maps accepted by CacheService
        final toSave = lista.map((m) => Map<String, dynamic>.from(m)).toList();
        await CacheService().saveEntregas(toSave);
      } catch (e) {
        debugPrint('Erro ao salvar cache (debounced): $e');
      }
    });
  }

  // TOOLS DE ÁUDIO
  // Única função de modal: `_buildSuccessModal` definida abaixo

  // Novas funções de áudio conforme especificação
  Future<void> _tocarSomFalha() async {
    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.stop();
      // IMPORTANTE: arquivos de áudio devem ficar em assets/audios/ e
      // serem registrados em pubspec.yaml. Evite alterar esse caminho.
      await _audioPlayer.play(AssetSource('audios/falha_3.mp3'));
      Future.delayed(Duration(seconds: 3), () async {
        try {
          await _audioPlayer.stop();
        } catch (_) {}
      });
    } catch (_) {}
  }

  Future<void> _tocarSomSucesso() async {
    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.stop();
      try {
        await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      } catch (_) {}
      // IMPORTANTE: arquivos de áudio devem ficar em assets/audios/ e
      // serem registrados em pubspec.yaml. Evite alterar esse caminho.
      await _audioPlayer.play(AssetSource('audios/chama.mp3'));
    } catch (_) {}
  }

  Future<void> _tocarSomRotaConcluida() async {
    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.stop();
      // IMPORTANTE: arquivos de áudio devem ficar em assets/audios/ e
      // serem registrados em pubspec.yaml. Evite alterar esse caminho.
      await _audioPlayer.play(AssetSource('audios/final.mp3'));
    } catch (_) {}
  }

  // Atualiza token FCM do dispositivo no registro do motorista no Supabase
  Future<void> _atualizarTokenNoBanco() async {
    // Firebase removed: função mantida como stub para compatibilidade.
    return;
  }

  // Atualiza o campo `esta_online` do motorista no Supabase
  Future<void> _atualizarStatusNoSupabase(bool status) async {
    if (_driverId == 0) return;
    try {
      await Supabase.instance.client
          .from('motoristas')
          .update({'esta_online': status})
          .eq('id', _driverId);
    } catch (e) {
      debugPrint('Erro status: $e');
    }
  }

  Widget _buildIndicatorCard({
    required IconData icon,
    required int count,
    required String label,
  }) {
    final lc = label.toLowerCase();
    final borderColor = lc.contains('entrega')
        ? Colors.blue
        : lc.contains('recolh')
        ? Colors.orange
        : Colors.deepPurpleAccent;
    // Determina cores com base no esquema selecionado
    final Color backgroundColor;
    final Color textColor;
    final Color subtitleColor;

    if (_esquemaCores == 1) {
      // Modo 1 (Cinza)
      backgroundColor = Colors.grey[800]!;
      textColor = Colors.white;
      subtitleColor = Colors.white70;
    } else if (_esquemaCores == 2) {
      // Modo 2 (Marrom Claro)
      backgroundColor = const Color(0xFFD7CCC8);
      textColor = Colors.black;
      subtitleColor = Colors.black54;
    } else if (_esquemaCores == 3) {
      // Modo 3 (Dia - Destaque)
      backgroundColor = Colors.grey[100]!;
      textColor = Colors.black;
      subtitleColor = Colors.black54;
    } else {
      // Fallback (mantém compatibilidade)
      backgroundColor = const Color(0xFF4E342E);
      textColor = Colors.white;
      subtitleColor = Colors.white70;
    }

    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Color(0x4D000000), blurRadius: 6, spreadRadius: 1),
        ],
        border: Border.all(color: borderColor, width: 2.0),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: textColor, size: 30),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: TextStyle(
              color: textColor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: subtitleColor, fontSize: 12)),
        ],
      ),
    );
  }

  // Função que inicia loop do som de chamada (se ainda desejar loop contínuo)
  Future<void> _startChamaLoop() async {
    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.stop();
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      // IMPORTANTE: arquivos de áudio devem ficar em assets/audios/ e
      // serem registrados em pubspec.yaml. Evite alterar esse caminho.
      await _audioPlayer.play(AssetSource('audios/chama.mp3'));
    } catch (_) {}
  }

  // Parar qualquer áudio em reprodução
  Future<void> _pararAudio() async {
    try {
      _awaitStartChama = false;
      await _audioPlayer.stop();
      try {
        await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      } catch (_) {}
    } catch (_) {}
  }

  // Envia relatório de falha para o gestor, toca som, remove o card e fecha modal
  Future<void> _enviarFalha(
    String cardId,
    String cliente,
    String endereco,
    String motivoFinal,
    String detalhesObs,
  ) async {
    final hora = DateFormat('HH:mm').format(DateTime.now());
    final hasPhoto = imagemFalha != null;

    final report =
        '*Status:* falha\n'
        '*Motivo:* $motivoFinal\n'
        '${detalhesObs.isNotEmpty ? '*Detalhes:* $detalhesObs\n' : ''}'
        '*Cliente:* $cliente\n'
        '*Endereço:* $endereco\n'
        '*Motorista:* $nomeMotorista\n'
        '*Hora:* $hora';

    // Parar qualquer som de fundo antes de processar
    try {
      await _pararAudio();
    } catch (e) {
      // ignorar
    }

    // 1) SALVAR no Supabase primeiro (ordem de segurança requerida)
    try {
      await Supabase.instance.client
          .from('entregas')
          .update({
            'status': 'falha',
            'obs': detalhesObs,
            'data_conclusao': DateTime.now().toIso8601String(),
          })
          .eq('id', cardId);
    } catch (e) {
      debugPrint('Erro ao salvar falha no Supabase: $e');
    }

    // 2) Atualizar UI local e persistir estado
    // Nota: não atualizar a UI imediatamente aqui (evitar setState durante
    // abertura de apps externos). A atualização será feita quando o motorista
    // retornar ao app via `_postFalhaCleanup`.
    try {
      await CacheService().saveEntregas(
        List<Map<String, dynamic>>.from(
          entregas.map((e) => Map<String, dynamic>.from(e as Map)),
        ),
      );
    } catch (e) {
      debugPrint('Erro salvando cache antes do compartilhamento: $e');
    }

    // 4) Agora executar o envio/desacoplado (compartilhar arquivo ou Whatsapp)
    bool sharedSuccess = false;
    try {
      if (hasPhoto && imagemFalha != null) {
        final f = File(imagemFalha!);
        if (await f.exists()) {
          sharedSuccess = await finalizarEnvio(f, report);
        } else {
          sharedSuccess = false;
          try {
            await _enviarWhatsApp(report, phone: numeroGestor);
            sharedSuccess = true;
          } catch (_) {}
        }
      } else {
        try {
          await _enviarWhatsApp(report, phone: numeroGestor);
          sharedSuccess = true;
        } catch (_) {
          sharedSuccess = false;
        }
      }
    } catch (e) {
      debugPrint('Erro no compartilhamento: $e');
      sharedSuccess = false;
    }

    // Limpar preview da foto APÓS compartilhamento bem-sucedido
    // Nota: não chamar setState aqui — a limpeza será feita por
    // `_postFalhaCleanup` quando o usuário retornar ao app.

    // Forçar redraw após retorno de app externo (ex: WhatsApp)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        setState(() {});
      } catch (_) {}
    });

    // Se não há mais entregas, tocar som de rota concluída (mantido em código ativo quando necessário)
  }

  // Limpeza local após o motorista retornar ao app: atualiza UI e cache.
  Future<void> _postFalhaCleanup(String cardId) async {
    if (!mounted) return;
    try {
      setState(() {
        _entregas.removeWhere(
          (item) => item['id'].toString() == cardId.toString(),
        );
        _atualizarContadores();
        imagemFalha = null;
        motivoFalhaSelecionada = null;
      });
    } catch (e) {
      debugPrint('Erro ao aplicar cleanup de falha na UI: $e');
    }
    try {
      await CacheService().saveEntregas(
        List<Map<String, dynamic>>.from(
          entregas.map((e) => Map<String, dynamic>.from(e as Map)),
        ),
      );
    } catch (e) {
      debugPrint('Erro salvando cache após cleanup: $e');
    }
    try {
      _notifyEntregasDebounced(entregas);
    } catch (_) {}
  }

  // Centraliza reset das fotos usadas pelos modais (sucesso / falha)
  void _resetModalPhotos() {
    try {
      if (!mounted) return;
      setState(() {
        fotoEvidencia = null;
        imagemFalha = null;
        motivoFalhaSelecionada = null;
      });
    } catch (_) {}
  }

  // Função desacoplada que executa o compartilhamento de arquivo (retorna true se sucesso)
  Future<bool> finalizarEnvio(File? foto, String mensagem) async {
    try {
      if (foto != null) {
        final exists = await foto.exists().catchError((_) => false);
        final String p = foto.path;
        final bool isSuccessPhoto =
            fotoEvidencia != null && fotoEvidencia!.path == p;
        final bool isFailPhoto = imagemFalha != null && imagemFalha == p;
        if (exists && (isSuccessPhoto || isFailPhoto)) {
          try {
            // ignore: deprecated_member_use
            await Share.shareXFiles([XFile(p)], text: mensagem);
            try {
              _resetModalPhotos();
            } catch (_) {}
            return true;
          } catch (shareErr) {
            debugPrint('Erro ao usar Share.shareXFiles: $shareErr');
            // continuar para fallback
          }
        } else {
          debugPrint(
            'Arquivo de foto não pertence ao modal atual ou não existe: $p',
          );
        }
      }

      // Tentar abrir WhatsApp nativo (sem foto ou se share falhar)
      try {
        final String textEncoded = Uri.encodeComponent(mensagem);
        final String phone = (numeroGestor ?? '').replaceAll('+', '');
        final Uri uriWhatsApp = Uri.parse(
          'whatsapp://send?phone=$phone&text=$textEncoded',
        );
        if (await canLaunchUrl(uriWhatsApp)) {
          await launchUrl(uriWhatsApp, mode: LaunchMode.externalApplication);
          try {
            _resetModalPhotos();
          } catch (_) {}
          return true;
        }
      } catch (waErr) {
        debugPrint('Erro ao tentar abrir WhatsApp nativo: $waErr');
      }

      // Fallback para _enviarWhatsApp (usa api.whatsapp.com / https)
      try {
        await _enviarWhatsApp(mensagem, phone: numeroGestor);
        try {
          _resetModalPhotos();
        } catch (_) {}
        return true;
      } catch (fbErr) {
        debugPrint('Erro no fallback _enviarWhatsApp: $fbErr');
        // Último recurso: compartilhar apenas texto
        try {
          await Share.share(mensagem);
          try {
            _resetModalPhotos();
          } catch (_) {}
          return true;
        } catch (finalErr) {
          debugPrint('Erro ao compartilhar texto: $finalErr');
          return false;
        }
      }
    } catch (e) {
      debugPrint('finalizarEnvio erro inesperado: $e');
      return false;
    }
  }

  Future<void> _salvarMapaSelecionado(String mapName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefSelectedMapKey, mapName);
    setState(() => _selectedMapName = mapName);
  }

  // Modal de FALHA (structuralmente espelhado ao modal de sucesso, tema vermelho)
  void _buildFailModal(BuildContext ctx, Map<String, dynamic> item) {
    final String nomeCliente = item['cliente'] ?? '';
    _resetModalPhotos();
    String? motivoSelecionadoLocal;
    String obsTexto = '';
    XFile? pickedImageLocal;
    final TextEditingController obsController = TextEditingController();

    showDialog(
      context: ctx,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx2, setStateDialog) {
            final List<String> motivos = [
              'Cliente Ausente',
              'Endereço não localizado',
              'Local Fechado',
              'Recusou Entrega',
              'Mudou-se',
              'Área de Risco',
              'Veículo Quebrado',
              'Outro Motivo',
            ];

            final Color bg = modoDia ? Colors.white : Colors.grey[900]!;
            final Color textColor = modoDia ? Colors.black87 : Colors.white;
            final Color secondary = modoDia ? Colors.black54 : Colors.white70;
            final Color fillColor = modoDia
                ? Colors.grey.shade200
                : Colors.white10;

            final bool hasPhoto =
                (imagemFalha != null) || (pickedImageLocal != null);
            // Foto agora é opcional: habilitar envio assim que um motivo for selecionado
            final bool canSend =
                (motivoSelecionadoLocal != null) ||
                (motivoFalhaSelecionada != null);

            return AlertDialog(
              backgroundColor: bg,
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'FALHA',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.left,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.camera_alt, color: textColor),
                    onPressed: () async {
                      final XFile? photo = await _tirarFoto();
                      if (photo != null) {
                        setState(() {
                          imagemFalha = photo.path;
                          caminhoFotoSession = photo.path;
                        });
                        setStateDialog(() => pickedImageLocal = photo);
                      }
                    },
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.9,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Preview da foto (120x120) centralizado
                      Center(
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: fillColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: textColor.withOpacity(0.2),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: hasPhoto
                                ? Builder(
                                    builder: (_) {
                                      final String path =
                                          pickedImageLocal?.path ??
                                          imagemFalha ??
                                          '';
                                      if (path.isNotEmpty) {
                                        try {
                                          return Image.file(
                                            File(path),
                                            fit: BoxFit.cover,
                                            width: 120,
                                            height: 120,
                                          );
                                        } catch (_) {
                                          // Em caso de falha ao carregar imagem, mostrar ícone
                                          return Center(
                                            child: Icon(
                                              Icons.photo,
                                              color: secondary,
                                              size: 36,
                                            ),
                                          );
                                        }
                                      }
                                      return Center(
                                        child: Icon(
                                          Icons.photo,
                                          color: secondary,
                                          size: 36,
                                        ),
                                      );
                                    },
                                  )
                                : Center(
                                    child: Icon(
                                      Icons.photo,
                                      color: secondary,
                                      size: 36,
                                    ),
                                  ),
                          ),
                        ),
                      ),

                      SizedBox(height: 12),

                      GridView.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.1,
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        children: motivos.map((m) {
                          final bool isSel =
                              motivoSelecionadoLocal == m ||
                              motivoFalhaSelecionada == m;
                          return ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isSel
                                  ? Colors.red
                                  : Colors.grey[800],
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 6,
                              ),
                            ),
                            onPressed: () {
                              setStateDialog(() => motivoSelecionadoLocal = m);
                              setState(() => motivoFalhaSelecionada = m);
                            },
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                m,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, height: 1.1),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      SizedBox(height: 12),

                      TextField(
                        controller: obsController,
                        decoration: InputDecoration(
                          labelText: 'Observações',
                          filled: true,
                          fillColor: fillColor,
                          border: OutlineInputBorder(),
                          labelStyle: TextStyle(color: secondary),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        style: TextStyle(color: textColor),
                        onChanged: (v) => setStateDialog(() => obsTexto = v),
                        maxLines: 2,
                      ),

                      SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canSend
                            ? Colors.red
                            : Colors.grey[700],
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      onPressed: canSend
                          ? () async {
                              final idItem = item['id'];
                              final cliente = item['cliente'] ?? '';
                              final endereco = item['endereco'] ?? '';
                              final motivoFinal =
                                  motivoSelecionadoLocal ??
                                  motivoFalhaSelecionada ??
                                  '';
                              final detalhes = obsTexto.trim();

                              final payload = {
                                'status': 'falha',
                                'tipo_recebedor': motivoFinal,
                                'obs': detalhes,
                                'data_conclusao': DateTime.now()
                                    .toIso8601String(),
                              };
                              try {
                                final dynamic res = await Supabase
                                    .instance
                                    .client
                                    .from('entregas')
                                    .update(payload)
                                    .eq('id', idItem)
                                    .select();
                                debugPrint('Update falha result: $res');
                              } catch (e) {
                                debugPrint(
                                  'Erro ao gravar falha no Supabase: $e',
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Erro ao salvar falha: ${e.toString().split('\n').first}',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }

                              // Segurança Máxima: primeiro disparar WhatsApp, manter modal aberto
                              final hora = DateFormat(
                                'HH:mm',
                              ).format(DateTime.now());
                              final report =
                                  '*Status:* falha\n'
                                  '*Motivo:* $motivoFinal\n'
                                  '${detalhes.isNotEmpty ? '*Detalhes:* $detalhes\n' : ''}'
                                  '*Cliente:* $cliente\n'
                                  '*Endereço:* $endereco\n'
                                  '*Motorista:* $nomeMotorista\n'
                                  '*Hora:* $hora';

                              try {
                                if (imagemFalha != null) {
                                  try {
                                    final f = File(imagemFalha!);
                                    if (await f.exists()) {
                                      await finalizarEnvio(f, report);
                                    } else {
                                      await _enviarWhatsApp(
                                        report,
                                        phone: numeroGestor,
                                      );
                                      try {
                                        _resetModalPhotos();
                                      } catch (_) {}
                                    }
                                  } catch (e) {
                                    debugPrint(
                                      'Erro ao anexar foto da falha: $e',
                                    );
                                    await _enviarWhatsApp(
                                      report,
                                      phone: numeroGestor,
                                    );
                                    try {
                                      _resetModalPhotos();
                                    } catch (_) {}
                                  }
                                } else {
                                  await _enviarWhatsApp(
                                    report,
                                    phone: numeroGestor,
                                  );
                                  try {
                                    _resetModalPhotos();
                                  } catch (_) {}
                                }
                              } catch (e) {
                                debugPrint('Erro ao disparar WhatsApp: $e');
                              }

                              // Delay de saída para dar tempo ao sistema abrir o app externo
                              await Future.delayed(const Duration(seconds: 1));
                              if (!mounted) return;
                              try {
                                if (Navigator.of(context).canPop())
                                  Navigator.of(context).pop();
                              } catch (e) {
                                debugPrint(
                                  'Erro ao fechar modal após envio: $e',
                                );
                              }

                              // Atualizar UI local APÓS o retorno do motorista
                              await _postFalhaCleanup(idItem.toString());
                            }
                          : null,
                      child: Text('ENVIAR PARA GESTOR'),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Única função de modal: abre o bottom sheet de sucesso
  void _buildSuccessModal(BuildContext ctx, Map<String, dynamic> item) {
    final String nomeCliente = item['cliente'] ?? '';
    _resetModalPhotos();
    String? opcaoSelecionada;
    String obsTexto = '';
    XFile? pickedImageLocal;
    final TextEditingController moradorController = TextEditingController();

    // Abrir modal tipo AlertDialog para espelhar o visual do modal de Falha
    showDialog(
      context: ctx,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx2, setStateDialog) {
            final optionsSuccess = _opcoesEntrega
                .where((o) => o != 'PRÓPRIO')
                .toList();

            final Color bg = modoDia ? Colors.white : Colors.grey[900]!;
            final Color textColor = modoDia ? Colors.black87 : Colors.white;
            final Color secondary = modoDia ? Colors.black54 : Colors.white70;
            final Color fillColor = modoDia
                ? Colors.grey.shade200
                : Colors.white10;

            return AlertDialog(
              backgroundColor: bg,
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'ENTREGA',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.left,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.camera_alt, color: textColor),
                    onPressed: () async {
                      final XFile? photo = await _tirarFoto();
                      if (photo != null) {
                        // armazenar em ambos os estados (pai e modal)
                        setState(() {
                          fotoEvidencia = photo;
                          caminhoFotoSession = photo.path;
                        });
                        setStateDialog(() => pickedImageLocal = photo);
                      }
                    },
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.9,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Sem placeholder de foto central (apenas câmera no canto superior direito)

                      // Seletor de opções (grid 2 colunas) com padding idêntico
                      GridView.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.1,
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        children: optionsSuccess.map((opcao) {
                          final bool isSel = opcaoSelecionada == opcao;
                          return ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isSel
                                  ? Colors.green
                                  : Colors.grey[800],
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () {
                              setStateDialog(() => opcaoSelecionada = opcao);
                              setState(() => opcaoSelecionada = opcao);
                            },
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                opcao,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, height: 1.1),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      SizedBox(height: 12),

                      // Campo Nome removido — usar Observações para Nome

                      // Campo adicional para MORADOR: digitar número (oculto por padrão)
                      if (opcaoSelecionada == 'MORADOR') ...[
                        Row(
                          children: [
                            SizedBox(
                              width: 120,
                              child: TextField(
                                controller: moradorController,
                                keyboardType: TextInputType.phone,
                                style: TextStyle(color: textColor),
                                decoration: InputDecoration(
                                  hintText: 'Nº',
                                  hintStyle: TextStyle(color: secondary),
                                  filled: true,
                                  fillColor: fillColor,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                ),
                                onChanged: (_) => setStateDialog(() {}),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(child: SizedBox()),
                          ],
                        ),
                        SizedBox(height: 8),
                      ],

                      // Botão ENVIAR foi movido para abaixo das Observações.
                      SizedBox(height: 8),

                      // Observações (usado como Nome agora)
                      TextField(
                        decoration: InputDecoration(
                          labelText: 'Nome / Observações',
                          filled: true,
                          fillColor: fillColor,
                          border: OutlineInputBorder(),
                          labelStyle: TextStyle(color: secondary),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        style: TextStyle(color: textColor),
                        onChanged: (v) => setStateDialog(() => obsTexto = v),
                        maxLines: 1,
                      ),

                      SizedBox(height: 12),

                      // Botão ENVIAR agora abaixo das Observações
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                ((opcaoSelecionada != null) ||
                                    (obsTexto.trim().length >= 3))
                                ? Colors.green
                                : Colors.grey[700],
                            padding: EdgeInsets.symmetric(vertical: 12),
                            textStyle: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          onPressed:
                              ((opcaoSelecionada != null) ||
                                  (obsTexto.trim().length >= 3))
                              ? () async {
                                  // Monta 'recebidoPor' conforme regras:
                                  // *Recebido por:* [OPCAO] [CONTEUDO_OBSERVACOES] ([CONTEUDO_Nº])
                                  String recebidoPor = '-';
                                  final nomeTxt = obsTexto.trim();
                                  final numTxt = moradorController.text.trim();
                                  if (opcaoSelecionada != null) {
                                    if (opcaoSelecionada == 'MORADOR') {
                                      if (nomeTxt.isNotEmpty &&
                                          numTxt.isNotEmpty) {
                                        recebidoPor =
                                            '${opcaoSelecionada!} $nomeTxt ($numTxt)';
                                      } else if (nomeTxt.isNotEmpty) {
                                        recebidoPor =
                                            '${opcaoSelecionada!} $nomeTxt';
                                      } else if (numTxt.isNotEmpty) {
                                        recebidoPor =
                                            '${opcaoSelecionada!} ($numTxt)';
                                      } else {
                                        recebidoPor = opcaoSelecionada!;
                                      }
                                    } else {
                                      recebidoPor = nomeTxt.isNotEmpty
                                          ? '${opcaoSelecionada!} $nomeTxt'
                                          : opcaoSelecionada!;
                                    }
                                  } else {
                                    recebidoPor = nomeTxt.isNotEmpty
                                        ? nomeTxt
                                        : '-';
                                  }

                                  try {
                                    await _audioPlayer.setVolume(1.0);
                                    await _audioPlayer.play(
                                      AssetSource('audios/sucesso.mp3'),
                                    );
                                  } catch (_) {}
                                  await Future.delayed(
                                    Duration(milliseconds: 500),
                                  );

                                  final hora = DateFormat(
                                    'HH:mm',
                                  ).format(DateTime.now());
                                  final enderecoCliente = entregas.firstWhere(
                                    (e) => (e['cliente'] ?? '') == nomeCliente,
                                    orElse: () => {'endereco': ''},
                                  )['endereco'];

                                  final mensagem =
                                      '*Status:* Sucesso\n'
                                      '*Recebido por:* $recebidoPor\n'
                                      '*Cliente:* $nomeCliente | *Endereço:* ${enderecoCliente ?? ''} | *Motorista:* $nomeMotorista | *Hora:* $hora';

                                  // anexar foto se existente (capturada aqui ou em sessão)
                                  final List<XFile> files = [];
                                  try {
                                    final String? pickedPathLocal =
                                        pickedImageLocal?.path;
                                    if (pickedPathLocal != null) {
                                      if (await File(
                                        pickedPathLocal,
                                      ).exists()) {
                                        files.add(XFile(pickedPathLocal));
                                      }
                                    } else {
                                      final String? fotoPath =
                                          fotoEvidencia?.path ??
                                          caminhoFotoSession;
                                      if (fotoPath != null) {
                                        if (await File(fotoPath).exists()) {
                                          files.add(XFile(fotoPath));
                                        }
                                      }
                                    }
                                  } catch (_) {}

                                  // Persistir no Supabase com as chaves corretas (id, cliente, endereco, tipo, obs)
                                  final idItem = item['id'];
                                  final payload = {
                                    'cliente': item['cliente'] ?? '',
                                    'endereco': item['endereco'] ?? '',
                                    'tipo_recebedor': opcaoSelecionada ?? '',
                                    'obs': obsTexto.trim(),
                                    'data_conclusao': DateTime.now()
                                        .toIso8601String(),
                                    'status': 'entregue',
                                  };

                                  try {
                                    dynamic res;
                                    try {
                                      res = await Supabase.instance.client
                                          .from('entregas')
                                          .update(payload)
                                          .eq('id', idItem)
                                          .select();
                                    } catch (e) {
                                      // Log específico solicitado
                                      debugPrint('ERRO NO UPDATE: $e');
                                      rethrow;
                                    }

                                    if (res is List && res.isNotEmpty) {
                                      // após persistir com sucesso, enviar foto/mensagem
                                      try {
                                        // Envio condicional explícito: OK envia apenas sua foto (`fotoEvidencia`)
                                        if (fotoEvidencia == null) {
                                          // Sem foto: enviar apenas texto via WhatsApp
                                          await _enviarWhatsApp(
                                            mensagem,
                                            phone: numeroGestor,
                                          );
                                          try {
                                            _resetModalPhotos();
                                          } catch (_) {}
                                        } else {
                                          // Com foto: enviar mídia + texto (usar apenas `fotoEvidencia`/picked local)
                                          try {
                                            final String? pathToSend =
                                                fotoEvidencia?.path ??
                                                pickedImageLocal?.path ??
                                                caminhoFotoSession;
                                            if (pathToSend != null) {
                                              // ignore: deprecated_member_use
                                              await Share.shareXFiles([
                                                XFile(pathToSend),
                                              ], text: mensagem);
                                            } else {
                                              // fallback para texto se arquivo não existir
                                              await _enviarWhatsApp(
                                                mensagem,
                                                phone: numeroGestor,
                                              );
                                            }
                                          } finally {
                                            try {
                                              _resetModalPhotos();
                                            } catch (_) {}
                                          }
                                        }
                                      } catch (e) {
                                        debugPrint(
                                          'Falha ao enviar mídia/mensagem: $e',
                                        );
                                      }

                                      // fechar modal e remover localmente
                                      if (!mounted) return;
                                      Navigator.pop(context);
                                      setState(() {
                                        entregas.removeWhere(
                                          (e) => e['id'] == idItem,
                                        );
                                        _atualizarContadores();
                                        fotoEvidencia = null;
                                        caminhoFotoSession = null;
                                      });
                                      // Notificar stream/UI que a lista mudou
                                      _notifyEntregasDebounced(
                                        List<dynamic>.from(entregas),
                                      );

                                      if (entregas.isEmpty) {
                                        try {
                                          await _tocarSomRotaConcluida();
                                        } catch (_) {}
                                      }
                                    } else {
                                      throw Exception(
                                        'Resposta inválida do Supabase: $res',
                                      );
                                    }
                                  } catch (e) {
                                    final err = e.toString();
                                    debugPrint(
                                      'Erro ao finalizar entrega: $err',
                                    );
                                    final m = RegExp(
                                      r'column "([^"]+)"',
                                    ).firstMatch(err);
                                    if (m != null) {
                                      debugPrint(
                                        'Coluna não encontrada no banco: ${m.group(1)}',
                                      );
                                    }
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '❌ Falha ao salvar no banco: ${err.split('\n').first}',
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                }
                              : null,
                          child: Text('ENVIAR PARA GESTOR'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _abrirPreferenciasMapa() async {
    try {
      final available = await MapLauncher.installedMaps;
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        builder: (ctx) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text('Usar mapa web (Google Maps)'),
                  onTap: () {
                    _salvarMapaSelecionado('google_maps');
                    Navigator.of(ctx).pop();
                  },
                ),
                ...available.map((m) {
                  return ListTile(
                    leading: Icon(Icons.map),
                    title: Text(m.mapName),
                    onTap: () {
                      _salvarMapaSelecionado(m.mapName);
                      Navigator.of(ctx).pop();
                    },
                  );
                }),
              ],
            ),
          );
        },
      );
    } catch (e) {
      // ignore
    }
  }

  // ignore: unused_element
  String _buildLinkParaWhatsApp(String endereco) {
    final encoded = Uri.encodeComponent(endereco);
    if ((_selectedMapName ?? '').toLowerCase().contains('waze')) {
      return 'https://waze.com/ul?q=$encoded';
    }
    // default e outros: Google Maps web link
    return 'https://www.google.com/maps/search/?api=1&query=$encoded';
  }

  void _atualizarContadores() {
    // Usar normalização (trim + lowercase) para evitar falhas por espaços/maiúsculas
    totalEntregas = entregas.where((e) {
      final tipoTratado = (e['tipo'] ?? '').toString().trim().toLowerCase();
      return tipoTratado.contains('entrega');
    }).length;

    totalRecolhas = entregas.where((e) {
      final tipoTratado = (e['tipo'] ?? '').toString().trim().toLowerCase();
      return tipoTratado.contains('recolh');
    }).length;

    // Outros são o restante dos itens
    totalOutros = entregas.length - totalEntregas - totalRecolhas;

    // Atualizar variáveis legadas que ainda podem ser usadas pelo app
    entregasFaltam = totalEntregas;
    recolhasFaltam = totalRecolhas;
    outrosFaltam = totalOutros;
  }

  // Carrega dados da tabela 'entregas' no Supabase e atualiza a lista local
  Future<void> carregarDados() async {
    try {
      // Se estiver em modo offline, não usar dados fictícios; tentar usar cache local
      if (modoOffline) {
        if (!mounted) return;
        try {
          final cached = await CacheService().loadEntregas();
          if (cached.isNotEmpty) {
            final lista = cached.map<Map<String, String>>((m) {
              return m.map((k, v) => MapEntry(k, v?.toString() ?? ''));
            }).toList();
            _setEntregas(List<dynamic>.from(lista));
            _atualizarContadores();
          } else {
            // sem cache: lista vazia
            _setEntregas([]);
            _atualizarContadores();
          }
        } catch (e) {
          _setEntregas([]);
          _atualizarContadores();
        }
        return;
      }
    } catch (e, st) {
      debugPrint('Erro em carregarDados(): $e');
      debugPrint('$st');
      if (mounted) {
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao carregar entregas: ${e.toString()}'),
            ),
          );
        } catch (_) {}
      }
      return;
    }
    // Checar conectividade básica antes de tentar alcançar o Supabase

    Future<bool> checarConexao() async {
      try {
        // Checa se há conectividade de rede (Wi-Fi/4G)
        final conn = await Connectivity().checkConnectivity();
        if (conn == ConnectivityResult.none) return false;

        // Verifica que existe acesso real à internet (resolução/ICMP-like)
        final has = await InternetConnectionChecker().hasConnection;
        return has;
      } catch (e) {
        return false;
      }
    }

    if (!await checarConexao()) {
      if (!mounted) return;
      setState(() => modoOffline = true);

      // Tentar carregar cache local primeiro
      try {
        final cached = await CacheService().loadEntregas();
        if (cached.isNotEmpty) {
          final lista = cached.map<Map<String, String>>((m) {
            return m.map((k, v) => MapEntry(k, v?.toString() ?? ''));
          }).toList();
          if (!mounted) return;
          setState(() {
            // Se não sabemos o motorista, mostrar lista vazia para evitar dados globais
            if (_driverId == 0) {
              entregas = <Map<String, String>>[];
            } else {
              // filtrar cache para incluir apenas entregas do motorista
              entregas = lista
                  .where(
                    (m) => (m['motorista_id'] ?? '') == _driverId.toString(),
                  )
                  .toList();
            }
            _atualizarContadores();
          });
        } else {
          if (!mounted) return;
          _setEntregas([]);
          _atualizarContadores();
        }
      } catch (e) {
        debugPrint('Erro ao carregar cache: $e');
        if (!mounted) return;
        _setEntregas([]);
        _atualizarContadores();
      }

      // iniciar tentativas de reconexão periódicas
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer.periodic(const Duration(seconds: 30), (t) async {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (await checarConexao()) {
          t.cancel();
          await carregarDados();
        }
      });
      return;
    }

    // Modo online: buscar dados reais no Supabase usando retry exponencial
    final r = RetryOptions(
      maxAttempts: 5,
      delayFactor: const Duration(seconds: 2),
    );

    try {
      // Tentar recuperar o `driverId` salvo no storage do foreground task
      String? storedId;
      try {
        storedId = await FlutterForegroundTask.getData<String>(key: 'driverId');
      } catch (e) {
        debugPrint('Erro ao ler driverId do foreground storage: $e');
        storedId = null;
      }

      String driverIdForQuery;
      if (storedId != null && storedId.isNotEmpty && storedId != '0') {
        driverIdForQuery = storedId;
      } else {
        debugPrint(
          '⚠️ carregarDados(): driverId salvo inválido ou ausente ("$storedId"). Abortando.',
        );
        _setEntregas([]);
        _atualizarContadores();
        return;
      }

      debugPrint('📥 Buscando dados para motorista $driverIdForQuery...');

      // Ler número do gestor dinamicamente da tabela `configuracoes` (chave 'gestor_phone')
      try {
        final dynamic configRes = await Supabase.instance.client
            .from('configuracoes')
            .select('valor')
            .eq('chave', 'gestor_phone')
            .single();
        String candidate = '';
        if (configRes != null) {
          if (configRes is Map && configRes['valor'] != null) {
            candidate = configRes['valor'].toString();
          } else if (configRes is String) {
            candidate = configRes;
          }
        }
        if (candidate.isNotEmpty) {
          if (mounted) setState(() => numeroGestor = candidate);
        }
      } catch (e) {
        debugPrint('Erro ao ler config gestor: $e');
      }
      debugPrint('📞 Gestor atual: $numeroGestor');

      // Fazer query ordenando por `ordem_logistica` asc para preservar sequência
      dynamic response = await r.retry(() async {
        return await Supabase.instance.client
            .from('entregas')
            .select('*')
            .eq('motorista_id', driverIdForQuery)
            .or('status.eq.pendente,status.eq.em_rota')
            .order('ordem_logistica', ascending: true);
      }, retryIf: (e) => e is SocketException || e is TimeoutException);

      if (!mounted) return;

      final listaRaw = response as List<dynamic>?;
      if (listaRaw != null) {
        final lista = listaRaw.map<Map<String, String>>((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return {
            'id': m['id']?.toString() ?? '',
            'cliente': m['cliente']?.toString() ?? '',
            'endereco': m['endereco']?.toString() ?? '',
            'tipo': m['tipo']?.toString() ?? 'entrega',
            'motorista_id': m['motorista_id']?.toString() ?? '',
            // incluir 'status' para preservarmos o estado do item
            'status': m['status']?.toString() ?? '',
            // manter compatibilidade com chave antiga 'obs' e adicionar 'observacoes'
            'obs': m['obs']?.toString() ?? '',
            'observacoes':
                m['observacoes']?.toString() ??
                m['observacao']?.toString() ??
                m['obs']?.toString() ??
                '',
            // ordem_logistica para ordenação local
            'ordem_logistica': m['ordem_logistica']?.toString() ?? '0',
          };
        }).toList();

        // Ordenar localmente por ordem_logistica (ascendente)
        // Itens com ordem_logistica nula/ inválida vão para o final.
        try {
          const high = 1000000000; // valor alto para empurrar nulos ao final
          lista.sort((a, b) {
            final aiRaw = a['ordem_logistica'];
            final biRaw = b['ordem_logistica'];
            final ai =
                int.tryParse(aiRaw == null || aiRaw == '' ? '' : aiRaw) ?? high;
            final bi =
                int.tryParse(biRaw == null || biRaw == '' ? '' : biRaw) ?? high;
            return ai.compareTo(bi);
          });
        } catch (_) {}

        // Validar que os resultados pertençam ao motorista carregado (usar driverIdForQuery)
        try {
          final ok = lista.every(
            (it) => (it['motorista_id'] ?? '') == driverIdForQuery,
          );
          if (!ok) {
            debugPrint(
              'Descartando resultados de entregas (carregarDados): motorista mismatch',
            );
            return;
          }
        } catch (_) {}

        // ================================================================
        // DETECÇÃO DE NOVO PEDIDO E DISPARO DE SOM chama.mp3
        // ================================================================

        final quantidadeAtual = lista.length;

        debugPrint('🔔 VERIFICAÇÃO DE SOM (chama.mp3):');
        debugPrint('   └─ Quantidade anterior: $_totalEntregasAntigo');
        debugPrint('   └─ Quantidade atual: $quantidadeAtual');

        // Detectar incremento: nova > antiga E já tivemos pelo menos um carregamento anterior
        if (_hasInitialSync && quantidadeAtual > _totalEntregasAntigo) {
          debugPrint(
            '   └─ ✅ INCREMENTO DETECTADO! (+${quantidadeAtual - _totalEntregasAntigo})',
          );
          debugPrint('   └─ 🔊 Tocando assets/audios/chama.mp3...');

          try {
            await _tocarSomSucesso();
            debugPrint('   └─ ✅ Som tocado com sucesso!');
          } catch (e) {
            debugPrint('   └─ ❌ ERRO ao tocar som: $e');
          }
        } else {
          if (!_hasInitialSync) {
            debugPrint('   └─ ⏭️  Primeira carga - som não tocará');
          } else if (quantidadeAtual == _totalEntregasAntigo) {
            debugPrint('   └─ 📊 Mesma quantidade - sem novos pedidos');
          } else {
            debugPrint('   └─ 📉 Quantidade diminuiu - pedido finalizado');
          }
        }

        // ================================================================

        // Atualizar contador antigo sempre para evitar loop de som
        _totalEntregasAntigo = quantidadeAtual;
        debugPrint('   └─ Variável atualizada para: $_totalEntregasAntigo');

        // A lista já vem ordenada por id desc; atualizar estado substituindo a lista
        _setEntregas(List<dynamic>.from(lista));
        _atualizarContadores();
        debugPrint('✅ Dados carregados: ${lista.length} registros');
        // Log produtivo de sucesso do polling
        debugPrint(
          '✅ Polling: [${lista.length}] entregas sincronizadas para o motorista [$driverIdForQuery]',
        );
        setState(() {
          modoOffline = false;
          // Se ainda não inicializamos o contador antigo, setar para o tamanho atual
          if (_totalEntregasAntigo == -1) {
            _totalEntregasAntigo = lista.length;
          }
          // Marcar que já tivemos ao menos um carregamento bem-sucedido
          _hasInitialSync = true;
        });
        // forçar rebuild adicional para garantir atualização imediata da UI
        if (mounted) setState(() {});
        debugPrint('Lista atualizada com ${lista.length} pedidos');

        // Salvar em cache local para uso offline (debounced)
        _saveToCacheDebounced(lista);

        _reconnectTimer?.cancel();
        debugPrint('Conexão estabelecida com sucesso!');
      }
    } on SocketException catch (_) {
      if (!mounted) return;
      setState(() => modoOffline = true);
      _setEntregas([]);
      _atualizarContadores();

      _reconnectTimer?.cancel();
      _reconnectTimer = Timer.periodic(const Duration(seconds: 30), (t) async {
        if (!mounted) {
          t.cancel();
          return;
        }
        try {
          await carregarDados();
        } catch (_) {}
        if (!modoOffline) t.cancel();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => modoOffline = true);
      _setEntregas([]);
      _atualizarContadores();
    }
  }

  // Função `_removerItem` removida (não referenciada)

  // Salva histórico e arquivos associados (executar em background)
  Future<void> _salvarHistoricoParaItem(
    Map<String, String> item,
    String horario,
    String status, {
    XFile? photo,
    String? caminhoFotoSess,
    String? caminhoAssinaturaSess,
  }) async {
    String? caminhoFotoLocal;
    if (photo != null) {
      try {
        final tmp = await getTemporaryDirectory();
        final dest =
            '${tmp.path}/foto_${DateTime.now().millisecondsSinceEpoch}${p.extension(photo.path)}';
        await photo.saveTo(dest);
        caminhoFotoLocal = dest;
      } catch (e) {
        // erro ignorado - remover logs de depuração
      }
    } else if (caminhoFotoSess != null) {
      caminhoFotoLocal = caminhoFotoSess;
    }

    final caminhoAssinaturaLocal = caminhoAssinaturaSess;

    historicoEntregas.add(
      ItemHistorico(
        nomeCliente: item['cliente'] ?? '',
        horario: horario,
        status: status,
        motivo: null,
        caminhoFoto: caminhoFotoLocal,
        caminhoAssinatura: caminhoAssinaturaLocal,
      ),
    );
  }

  // Finaliza entrega: remove imediatamente, toca efeitos, abre WhatsApp e salva histórico em background
  // Função `_finalizarEntrega` removida (não referenciada)

  // Compartilha foto + assinatura + texto via Share.shareXFiles
  // ignore: unused_element
  Future<void> _compartilharRelatorio(int index, String nomeRecebedor) async {
    if (index < 0 || index >= entregas.length) return;
    final item = Map<String, String>.from(entregas[index]);

    // horário para histórico (HH:MM)
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final horario = '$hh:$mm';

    // mensagem formatada com quebras de linha claras (uma informação por linha)
    String mensagem =
        '*📦 V10 DELIVERY - RELATÓRIO*\n\n'
        '*📍 Cliente:* ${item['cliente']}\n'
        '*🏠 Endereço:* ${item['endereco']}\n'
        '*👤 Recebido por:* ${nomeRecebedor.isNotEmpty ? nomeRecebedor : nomeMotorista}\n'
        '*🕒 Horário:* $horario\n'
        '*✅ Status:* entregue';

    // coletar arquivos existentes
    final List<XFile> files = [];
    try {
      if (fotoEvidencia != null) {
        if (await File(fotoEvidencia!.path).exists()) {
          files.add(XFile(fotoEvidencia!.path));
        }
      } else if (caminhoFotoSession != null) {
        if (await File(caminhoFotoSession!).exists()) {
          files.add(XFile(caminhoFotoSession!));
        }
      }

      // signature file removed from sharing flow
    } catch (e) {
      // erro ignorado - remover logs de depuração
    }

    // snapshots antes de limpar
    final snapshotPhoto = fotoEvidencia;
    final snapshotCaminhoFoto = caminhoFotoSession;

    // remover item imediatamente para o próximo card subir
    setState(() {
      entregas.removeAt(index);
      _atualizarContadores();
      fotoEvidencia = null;
      caminhoFotoSession = null;
    });

    HapticFeedback.lightImpact();

    // tocar som de sucesso curto
    try {
      await _tocarSomSucesso();
      await Future.delayed(Duration(milliseconds: 500));
    } catch (e) {
      // erro ignorado
    }

    // compartilhar (texto em linhas separadas)
    try {
      // usar API compatível; método `shareXFiles` está deprecado mas funcional
      // ignore: deprecated_member_use
      await Share.shareXFiles(files, text: mensagem);
    } catch (e) {
      // erro ignorado - remover logs de depuração
    }

    // salvar histórico em background
    _salvarHistoricoParaItem(
      item,
      horario,
      'Sucesso',
      photo: snapshotPhoto,
      caminhoFotoSess: snapshotCaminhoFoto,
      caminhoAssinaturaSess: null,
    );

    // comportamento pós-remocao
    if (entregas.isEmpty) {
      HapticFeedback.heavyImpact();
      try {
        await _tocarSomRotaConcluida();
      } catch (e) {
        // erro ignorado
      }
    } else {
      try {
        await _pararAudio();
      } catch (e) {
        // erro ignorado
      }
    }
  }

  // Abre a câmera e retorna a foto (ou null). Centraliza o fluxo de captura.
  Future<XFile?> _tirarFoto() async {
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 25,
        maxWidth: 800,
      );
      return photo;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(
          180.0,
        ), // Altura ajustada para os cards
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: modoDia
              ? SystemUiOverlayStyle.dark
              : SystemUiOverlayStyle.light,
          child: Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(
                context,
              ).padding.top, // Respeita a barra de status
              left: 15,
              right: 15,
              bottom: 10,
            ),
            decoration: BoxDecoration(
              color: modoDia ? Colors.white : Colors.black,
            ),
            child: Column(
              children: [
                // Linha Superior: Menu, Título e Notificações
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Lado Esquerdo: Menu Sanduíche
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Builder(
                        builder: (context) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.menu,
                                color: modoDia ? Colors.black : Colors.white,
                              ),
                              onPressed: () =>
                                  Scaffold.of(context).openEndDrawer(),
                            ),
                            const SizedBox(width: 6),
                            // Botão Online/Offline
                            GestureDetector(
                              onTap: () async {
                                try {
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  setState(() {
                                    _isOnline = !_isOnline;
                                  });
                                  await prefs.setBool('is_online', _isOnline);
                                  // Sincronizar status com Supabase
                                  try {
                                    await _atualizarStatusNoSupabase(_isOnline);
                                  } catch (e) {
                                    debugPrint(
                                      'Erro sincronizar status no toggle: $e',
                                    );
                                  }

                                  if (_isOnline) {
                                    // Start foreground service + polling
                                    await _startForegroundService();
                                    _startPolling();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Você está ONLINE'),
                                      ),
                                    );
                                  } else {
                                    // Stop service + polling
                                    await _stopForegroundService();
                                    _stopPolling();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Você está OFFLINE'),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  debugPrint('Erro toggling online: $e');
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: _isOnline
                                      ? Colors.green[600]
                                      : Colors.grey[700],
                                  shape: BoxShape.circle,
                                  boxShadow: _isOnline
                                      ? [
                                          BoxShadow(
                                            color: Colors.green.withOpacity(
                                              0.45,
                                            ),
                                            blurRadius: 8,
                                            spreadRadius: 1,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Icon(
                                  _isOnline
                                      ? Icons.person
                                      : Icons.person_outline,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Centro: Título do App
                    const Text(
                      'V10 Delivery',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // Lado Direito: indicador de polling + Balão de Chat com Badge
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Indicador de Polling: nuvem que pisca quando verifica e fica vermelha se offline
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: GestureDetector(
                              onTap: () {},
                              child: AnimatedOpacity(
                                opacity: _pollingOffline
                                    ? 1.0
                                    : (_pollingBlink ? 1.0 : 0.75),
                                duration: const Duration(milliseconds: 180),
                                child: Transform.scale(
                                  scale: _pollingBlink ? 1.18 : 1.0,
                                  child: Icon(
                                    Icons.cloud,
                                    color: _pollingOffline
                                        ? Colors.red
                                        : (modoDia
                                              ? Colors.green
                                              : Colors.lightGreenAccent),
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Stack(
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.chat_bubble,
                                  color: modoDia ? Colors.black : Colors.white,
                                ),
                                onPressed: () {
                                  showAvisosModal(
                                    context: context,
                                    buscarAvisos: _buscarAvisos,
                                    atualizarAvisosNaoLidas:
                                        _atualizarAvisosNaoLidas,
                                    esquemaCores: _esquemaCores,
                                    modoDia: modoDia,
                                  );
                                },
                              ),
                              // Badge Vermelho (Aparece se tiver mensagens)
                              if (mensagensNaoLidas > 0)
                                Positioned(
                                  right: 8,
                                  top: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    child: Text(
                                      mensagensNaoLidas > 9
                                          ? '9+'
                                          : '$mensagensNaoLidas',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                // Linha dos Cards Indicadores (Tudo em Branco/Transparente)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildIndicatorCard(
                      icon: Icons.person,
                      count: totalEntregas,
                      label: 'ENTREGAS',
                    ),
                    _buildIndicatorCard(
                      icon: Icons.inventory_2,
                      count: totalRecolhas,
                      label: 'RECOLHA',
                    ),
                    _buildIndicatorCard(
                      icon: Icons.more_horiz,
                      count: totalOutros,
                      label: 'OUTROS',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      endDrawer: FutureBuilder<SharedPreferences>(
        future: SharedPreferences.getInstance(),
        builder: (ctx, snap) {
          final prefs = snap.data;
          final drawerName = nomeMotorista;
          final drawerAvatar = prefs?.getString('avatar_path') ?? _avatarPath;
          ImageProvider? avatarProvider;
          if (drawerAvatar != null && drawerAvatar.isNotEmpty) {
            try {
              if (drawerAvatar.startsWith('http')) {
                avatarProvider = NetworkImage(drawerAvatar);
              } else {
                avatarProvider = FileImage(File(drawerAvatar));
              }
            } catch (_) {
              avatarProvider = null;
            }
          }

          return Drawer(
            backgroundColor: modoDia ? Colors.grey[100] : Colors.black,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Flexible header: safe top spacing via MediaQuery, minimal height
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    MediaQuery.of(context).padding.top + 12,
                    16,
                    12,
                  ),
                  decoration: BoxDecoration(color: Colors.grey[900]),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () async => _showAvatarPickerOptions(),
                        child: Container(
                          margin: const EdgeInsets.only(top: 4),
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            color: modoDia
                                ? Colors.blue[200]
                                : Colors.blue[700],
                            image: avatarProvider != null
                                ? DecorationImage(
                                    image: avatarProvider,
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: avatarProvider == null
                              ? Icon(
                                  Icons.person,
                                  color: modoDia
                                      ? Colors.blue[900]
                                      : Colors.white,
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Use FittedBox so long names scale down instead of overflowing
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          drawerName,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.refresh,
                    color: modoDia ? Colors.black87 : Colors.white70,
                  ),
                  title: Text(
                    'Sincronizar Banco de Dados',
                    style: TextStyle(
                      color: modoDia ? Colors.black : Colors.white,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await carregarDados();
                  },
                ),
                SizedBox.shrink(),
                ListTile(
                  leading: Icon(
                    Icons.wb_sunny,
                    color: modoDia ? Colors.black87 : Colors.white70,
                  ),
                  title: Text(
                    'Modo Dia',
                    style: TextStyle(
                      color: modoDia ? Colors.black : Colors.white,
                    ),
                  ),
                  trailing: modoDia
                      ? Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () {
                    setState(() => modoDia = !modoDia);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.wifi_off,
                    color: modoDia ? Colors.black87 : Colors.white70,
                  ),
                  title: Text(
                    'Modo Offline',
                    style: TextStyle(
                      color: modoDia ? Colors.black : Colors.white,
                    ),
                  ),
                  trailing: Switch(
                    value: modoOffline,
                    activeThumbColor: Colors.green,
                    onChanged: (val) async {
                      final navigator = Navigator.of(context);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('modo_offline', val);
                      setState(() {
                        modoOffline = val;
                      });
                      // Recarregar dados conforme o novo modo
                      await carregarDados();
                      if (!mounted) return;
                      navigator.pop();
                    },
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.palette, color: Colors.red),
                  title: Text(
                    '🎨 Cores dos Cards',
                    style: TextStyle(
                      color: modoDia ? Colors.black : Colors.white,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _abrirModalEsquemasCores(context);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.map,
                    color: modoDia ? Colors.green : Colors.blueAccent,
                  ),
                  title: Text(
                    'Configurar GPS',
                    style: TextStyle(
                      color: modoDia ? Colors.black : Colors.white,
                    ),
                  ),
                  trailing:
                      (_selectedMapName != null && _selectedMapName!.isNotEmpty)
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _selectedMapName!.toLowerCase().contains('waze')
                                  ? 'Waze'
                                  : (_selectedMapName!.toLowerCase().contains(
                                          'google',
                                        ) ||
                                        _selectedMapName == 'google_maps')
                                  ? 'Google'
                                  : 'Mapa',
                              style: TextStyle(
                                color: modoDia
                                    ? Colors.black54
                                    : Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.check, color: Colors.green, size: 18),
                          ],
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _abrirPreferenciasMapa();
                  },
                ),
                SafeArea(
                  bottom: true,
                  top: false,
                  child: ListTile(
                    leading: Icon(Icons.exit_to_app, color: Colors.red),
                    title: Text('Sair', style: TextStyle(color: Colors.red)),
                    onTap: () async {
                      // Fechar o drawer antes de mostrar a confirmação
                      Navigator.pop(context);
                      final Color bg = modoDia
                          ? Colors.white
                          : Colors.grey[900]!;
                      final Color textColor = modoDia
                          ? Colors.black
                          : Colors.white;

                      showDialog(
                        context: context,
                        builder: (ctx) {
                          return AlertDialog(
                            backgroundColor: bg,
                            content: Text(
                              'Deseja realmente sair?',
                              style: TextStyle(color: textColor),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: Text(
                                  'NÃO',
                                  style: TextStyle(color: textColor),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  Navigator.of(ctx).pop();
                                  // Capture NavigatorState before awaiting to avoid using
                                  // BuildContext across an async gap.
                                  final nav = Navigator.of(context);
                                  // limpar estado UI local imediatamente
                                  if (mounted) {
                                    setState(() {
                                      nomeMotorista = '';
                                      _avatarPath = null;
                                    });
                                  }
                                  try {
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    // tentar marcar motorista como offline no Supabase antes de limpar prefs
                                    try {
                                      // Preferir usar email salvo para localizar o motorista
                                      final savedEmail =
                                          prefs.getString('email_salvo') ??
                                          Supabase
                                              .instance
                                              .client
                                              .auth
                                              .currentUser
                                              ?.email;
                                      if (savedEmail != null &&
                                          savedEmail.isNotEmpty) {
                                        try {
                                          final client =
                                              Supabase.instance.client;
                                          await client
                                              .from('motoristas')
                                              .update({
                                                'status': 'offline',
                                                'esta_online': false,
                                                'lat': null,
                                                'lng': null,
                                              })
                                              .ilike('email', savedEmail);
                                        } catch (e) {
                                          debugPrint(
                                            'ERRO LOGOUT: falha ao atualizar status offline por email: $e',
                                          );
                                        }
                                      } else {
                                        // Fallback para telefone como antes
                                        final phone =
                                            prefs.getString('driver_phone') ??
                                            '';
                                        final tel = phone.replaceAll(
                                          RegExp(r'\D'),
                                          '',
                                        );
                                        if (tel.isNotEmpty) {
                                          try {
                                            final client =
                                                Supabase.instance.client;
                                            await client
                                                .from('motoristas')
                                                .update({
                                                  'status': 'offline',
                                                  'esta_online': false,
                                                  'lat': null,
                                                  'lng': null,
                                                })
                                                .eq('telefone', tel);
                                          } catch (e) {
                                            debugPrint(
                                              'ERRO LOGOUT: falha ao atualizar status offline por telefone: $e',
                                            );
                                          }
                                        }
                                      }
                                    } catch (_) {}
                                    // apenas desmarcar 'manter_logado' e remover dados de sessão
                                    try {
                                      await prefs.setBool(
                                        'manter_logado',
                                        false,
                                      );
                                    } catch (_) {}
                                    try {
                                      await prefs.remove('driver_id');
                                      await prefs.remove('driver_name');
                                      await prefs.remove('avatar_path');
                                    } catch (_) {}
                                    // NÃO remover email_salvo — usuário pediu para preservar
                                    idLogado = null;
                                    nomeMotorista = '';
                                  } catch (_) {}
                                  if (!mounted) return;
                                  Future.microtask(() {
                                    nav.pushAndRemoveUntil(
                                      MaterialPageRoute(
                                        builder: (_) => const SplashPage(),
                                      ),
                                      (route) => false,
                                    );
                                  });
                                },
                                child: Text(
                                  'SIM',
                                  style: TextStyle(color: Colors.redAccent),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF001F3F), Color(0xFF072A52)],
                ),
              ),
              child: entregas.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 96,
                            color: Colors.green,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Todas as entregas concluídas!',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Bom trabalho, Leandro!',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                          SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20.0,
                            ),
                            child: Column(
                              children: [
                                CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation(
                                    Color(0xFFFFD700),
                                  ),
                                ),
                                SizedBox(height: 12),
                                FadeTransition(
                                  opacity: _buscarOpacity,
                                  child: Text(
                                    '🔍 Procurando novas rotas na sua região...',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  : StreamBuilder<List<dynamic>>(
                      stream: _entregasController.stream,
                      initialData: entregas,
                      builder: (ctx, snap) {
                        final listaEntregas = snap.data ?? entregas;
                        if (listaEntregas.isEmpty) {
                          return Center(
                            child: Text('Nenhuma entrega disponível'),
                          );
                        }
                        return RefreshIndicator(
                          color: Colors.blue,
                          onRefresh: carregarDados,
                          child: ReorderableListView.builder(
                            scrollController: _entregasScrollController,
                            physics: AlwaysScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            proxyDecorator: (child, index, animation) =>
                                Material(
                                  elevation: 20,
                                  color: Colors.transparent,
                                  child: child,
                                ),
                            itemCount: listaEntregas.length,
                            onReorder: (old, newIdx) {
                              setState(() {
                                if (newIdx > old) newIdx -= 1;
                                final item = listaEntregas.removeAt(old);
                                listaEntregas.insert(newIdx, item);
                                // refletir mudança no estado centralizado
                                _setEntregas(List<dynamic>.from(listaEntregas));
                              });
                            },
                            itemBuilder: (context, index) =>
                                ReorderableDelayedDragStartListener(
                                  key: ValueKey(listaEntregas[index]["id"]),
                                  index: index,
                                  child: _buildCard(
                                    listaEntregas[index],
                                    index,
                                  ),
                                ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, String> item, int index) {
    // Normalizar 'tipo' antes da comparação e debugar o valor exato recebido
    final tipoTratado = (item['tipo'] ?? '').toString().trim().toLowerCase();
    debugPrint('Tipo recebido: |${item['tipo']}|');

    // Fixar cor da barra lateral conforme tipo (ENTREGA, RECOLHA, OUTROS)
    final corItem = tipoTratado == 'entrega'
        ? Colors.blue
        : tipoTratado == 'recolha'
        ? Colors.orange
        : tipoTratado == 'outros'
        ? Colors.deepPurpleAccent
        : Colors.grey;
    final Color corBarra = corItem;

    final bool pressed = _pressedIndices.contains(index);
    final double scale = pressed ? 0.98 : 1.0;

    // Forçar fundo branco e texto escuro para consistência visual
    final Color fillColor = Colors.white;
    final Color textPrimary = Colors.black;
    final Color textSecondary = Colors.black87;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            offset: Offset(0, 8),
            blurRadius: 16,
          ),
        ],
        border: Border.all(color: corBarra, width: 2.0),
      ),
      // Ajuste do padding do card
      padding: EdgeInsets.all(20),
      child: Row(
        children: [
          // Indicador lateral arredondado
          Container(
            width: 10,
            height: 80,
            decoration: BoxDecoration(
              color: corBarra,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTapDown: (_) => setState(() => _pressedIndices.add(index)),
              onTapUp: (_) => setState(() => _pressedIndices.remove(index)),
              onTapCancel: () => setState(() => _pressedIndices.remove(index)),
              child: AnimatedContainer(
                duration: Duration(milliseconds: 200),
                transform: Matrix4.diagonal3Values(scale, scale, 1.0),
                transformAlignment: Alignment.center,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cabeçalho compacto: número e tipo na mesma linha
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: corBarra,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              // Stroke
                              Text(
                                item['tipo']!.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  foreground: Paint()
                                    ..style = PaintingStyle.stroke
                                    ..strokeWidth = 1.6
                                    ..color = corBarra,
                                ),
                              ),
                              // Fill
                              Text(
                                item['tipo']!.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 6),

                    // CLIENTE e ENDEREÇO com hierarquia visual
                    Text(
                      'CLIENTE',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    SizedBox(height: 6),
                    // Cliente (estilo fixo: preto, maior e em negrito)
                    Text(
                      item['cliente'] ?? '',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'ENDEREÇO',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    SizedBox(height: 6),
                    Text(
                      item['endereco'] ?? '',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),

                    // Observações/aviso do gestor (usar obrigatoriamente 'observacoes')
                    Builder(
                      builder: (ctx) {
                        // DEBUG: mostrar chaves recebidas do banco
                        try {
                          debugPrint('Colunas disponíveis: ${item.keys}');
                        } catch (_) {}

                        final obs =
                            item['observacoes'] ??
                            item['observacao'] ??
                            item['obs'] ??
                            '';
                        final displayText =
                            'Gestor: ${obs.toString().trim().isNotEmpty ? obs : 'Sem avisos no DB'}';

                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Container(
                            padding: EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(12),
                                topRight: Radius.circular(12),
                                bottomRight: Radius.circular(12),
                                bottomLeft: Radius.circular(0),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline,
                                  size: 16,
                                  color: Colors.blueGrey,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    displayText,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    SizedBox(height: 12),

                    // Ações do card: ROTA | FALHA | OK (estilo pill, cada botão expandido)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: ElevatedButton.icon(
                              icon: Icon(
                                Icons.map,
                                color: Colors.white,
                                size: 16,
                              ),
                              label: Text(
                                'ROTA',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                padding: EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () {
                                try {
                                  final endereco = item['endereco'] ?? '';
                                  _abrirMapaComPreferencia(endereco);
                                } catch (e) {
                                  debugPrint('Erro ao abrir mapa: $e');
                                }
                              },
                            ),
                          ),
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: ElevatedButton.icon(
                              icon: Icon(
                                Icons.error_outline,
                                color: Colors.white,
                                size: 16,
                              ),
                              label: Text(
                                'FALHA',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                padding: EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () {
                                try {
                                  setState(() {
                                    imagemFalha = null;
                                    fotoEvidencia = null;
                                  });
                                  _buildFailModal(
                                    context,
                                    Map<String, dynamic>.from(item),
                                  );
                                } catch (e) {
                                  debugPrint(
                                    'Erro ao abrir modal de falha: $e',
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: ElevatedButton.icon(
                              icon: Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 16,
                              ),
                              label: Text(
                                'OK',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                padding: EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () {
                                try {
                                  setState(() {
                                    imagemFalha = null;
                                    fotoEvidencia = null;
                                  });
                                  _buildSuccessModal(
                                    context,
                                    Map<String, dynamic>.from(item),
                                  );
                                } catch (e) {
                                  debugPrint(
                                    'Erro ao abrir modal de sucesso: $e',
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirMapaComPreferencia(String endereco) async {
    final encoded = Uri.encodeComponent(endereco);

    final googleMapsUrl =
        'https://www.google.com/maps/dir/?api=1&destination=$encoded';
    try {
      final uri = Uri.parse(googleMapsUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Não foi possível abrir o mapa.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Erro ao abrir mapa: $e');
    }
  }

  // ` _buildIndicatorCard` removed — header simplified and indicators unused

  void _abrirModalEsquemasCores(BuildContext context) {
    final Color bg = modoDia ? Colors.white : Colors.grey[900]!;
    final Color textColor = modoDia ? Colors.black : Colors.white;

    showModalBottomSheet(
      context: context,
      backgroundColor: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(height: 12),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      'Cores dos Cards',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Spacer(),
                  ],
                ),
              ),
              SizedBox(height: 8),
              ListTile(
                title: Text('Padrão', style: TextStyle(color: textColor)),
                onTap: () async {
                  final navigator = Navigator.of(ctx);
                  setState(() => _esquemaCores = 0);
                  try {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('modo_cores', 0);
                  } catch (_) {}
                  navigator.pop();
                },
                trailing: _esquemaCores == 0
                    ? Icon(Icons.check, color: Colors.green)
                    : null,
              ),
              ListTile(
                title: Text('Modo 1', style: TextStyle(color: textColor)),
                onTap: () async {
                  final navigator = Navigator.of(ctx);
                  setState(() => _esquemaCores = 1);
                  try {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('modo_cores', 1);
                  } catch (_) {}
                  navigator.pop();
                },
                trailing: _esquemaCores == 1
                    ? Icon(Icons.check, color: Colors.green)
                    : null,
              ),
              ListTile(
                title: Text('Modo 2', style: TextStyle(color: textColor)),
                onTap: () async {
                  final navigator = Navigator.of(ctx);
                  setState(() => _esquemaCores = 2);
                  try {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('modo_cores', 2);
                  } catch (_) {}
                  navigator.pop();
                },
                trailing: _esquemaCores == 2
                    ? Icon(Icons.check, color: Colors.green)
                    : null,
              ),
              SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  // ignore: unused_element
  Widget _buildOpcaoEsquema({
    required BuildContext context,
    required String titulo,
    required String subtitulo,
    required List<Color> cores,
    required int indice,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() => _esquemaCores = indice);
        Navigator.pop(context);
      },
      child: Container(
        decoration: BoxDecoration(
          color: _esquemaCores == indice ? Colors.blue[50] : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _esquemaCores == indice ? Colors.blue : Colors.grey[300]!,
            width: _esquemaCores == indice ? 2 : 1,
          ),
        ),
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  colors: cores,
                  stops: [0.3, 0.6, 0.9],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text(
                    subtitulo,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            if (_esquemaCores == indice)
              Icon(Icons.check_circle, color: Colors.blue),
          ],
        ),
      ),
    );
  }

  // helper removido: uso de opacidade não é mais necessário
}

class HistoricoAtividades extends StatelessWidget {
  final List<ItemHistorico> historico;
  final Future<void> Function(ItemHistorico) onResend;

  const HistoricoAtividades({
    super.key,
    required this.historico,
    required this.onResend,
  });

  @override
  Widget build(BuildContext context) {
    final entregues = historico
        .where((h) => h.status.toLowerCase().contains('sucesso'))
        .length;
    final falhas = historico
        .where((h) => h.status.toLowerCase().contains('falha'))
        .length;
    final total = historico.length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        title: const Text(
          'Histórico de Atividades',
          style: TextStyle(color: Colors.black),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _smallCard('Entregues', entregues.toString(), Colors.green),
                _smallCard('Falhas', falhas.toString(), Colors.red),
                _smallCard('Total', total.toString(), Colors.blue[900]!),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              physics: AlwaysScrollableScrollPhysics(),
              itemCount: historico.length,
              itemBuilder: (ctx, i) {
                final entry =
                    historico[historico.length -
                        1 -
                        i]; // mostrar do mais recente
                final isEntrega = entry.status.toLowerCase().contains(
                  'sucesso',
                );
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 6,
                      height: double.infinity,
                      color: isEntrega ? Colors.green : Colors.red,
                    ),
                    title: Text(entry.nomeCliente),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.horario),
                        if (entry.motivo != null)
                          Text('Motivo: ${entry.motivo}'),
                        Row(
                          children: [
                            if (entry.caminhoFoto != null)
                              Icon(Icons.camera_alt, size: 16),
                            SizedBox(width: 6),
                            if (entry.caminhoAssinatura != null)
                              Icon(Icons.draw, size: 16),
                          ],
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.chat, color: Colors.green),
                      onPressed: () => onResend(entry),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallCard(String label, String value, Color color) {
    return Container(
      width: 100,
      height: 80,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
