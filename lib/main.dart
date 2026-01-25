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

import 'services/cache_service.dart';
import 'widgets/avisos_modal.dart';

// Número do gestor (formato internacional sem +). Configure aqui.
const String numeroGestor = '5548996525008';
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

final List<ItemHistorico> historicoEntregas = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  runApp(const MyApp());
}

class V10DeliveryApp extends StatelessWidget {
  const V10DeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(),
      themeMode: ThemeMode.light,
      home: RotaMotorista(),
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
  final String nomeMotorista = "LEANDRO";
  String? _avatarPath;

  Future<void> _pickAndSaveAvatar(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? img = await picker.pickImage(
        source: source,
        imageQuality: 80,
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

  // Lista inicial vazia — será preenchida por `carregarDados()`
  List<dynamic> entregas = [];
  // Lista local de avisos (cache curto) — limpa quando houver eventos Realtime
  final List<Map<String, dynamic>> _avisosLocal = <Map<String, dynamic>>[];
  // Subscription Realtime para avisos_gestor (guardamos para cancelar)
  dynamic _avisosSubscription;
  // Polling fallback para entregas quando Realtime não funcionar
  // Inicializar com 0 para que um novo registro com id=1 seja detectado
  int _lastEntregaId = 0;
  // Controle para evitar tocar som no primeiro carregamento
  int _totalEntregasAntigo = -1;
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
    // iniciar cache service (não bloqueante)
    CacheService().init().catchError((e) => debugPrint('Cache init error: $e'));
    // Manter a tela acesa enquanto o app estiver em primeiro plano
    try {
      WakelockPlus.enable();
    } catch (_) {}
    super.initState();
    // Garantir cache limpo e lista inicial vazia (teste: DB reiniciado com id=1)
    CacheService().saveEntregas(<Map<String, dynamic>>[]).then((_) {
      if (!mounted) return;
      setState(() {
        entregas = [];
        _lastEntregaId = 0;
      });
    }).catchError((e) {
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

    // Registrar polling curto para verificar novos pedidos na tabela `entregas`.
    try {
      _entregasScrollController = ScrollController();
      _entregasPollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        try {
          // Buscar lista recente (limitada) e comparar tamanho com a lista local
          final res = await Supabase.instance.client
              .from('entregas')
              .select('*')
              .eq('motorista_id', '1')
              .order('id', ascending: false)
              .limit(50);
          final list = res as List<dynamic>? ?? <dynamic>[];

          // Normalizar para o mesmo formato usado em _setEntregas
          final novaLista = list.map<Map<String, String>>((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return {
              'id': m['id']?.toString() ?? '',
              'cliente': m['cliente']?.toString() ?? '',
              'endereco': m['endereco']?.toString() ?? '',
              'tipo': m['tipo']?.toString() ?? 'entrega',
              'status': m['status']?.toString() ?? '',
              'obs': m['obs']?.toString() ?? '',
              'observacoes': m['observacoes']?.toString() ?? m['observacao']?.toString() ?? m['obs']?.toString() ?? '',
            };
          }).toList();

          // Gestão de som: não tocar no primeiro carregamento
          if (_totalEntregasAntigo == -1) {
            // primeira vez: apenas inicializar o contador sem tocar
            if (!mounted) return;
            setState(() {
              entregas = List<dynamic>.from(novaLista);
              _atualizarContadores();
              _totalEntregasAntigo = novaLista.length;
            });
            // garantir que o StreamBuilder receba o novo valor imediatamente
            try {
              if (!_entregasController.isClosed) _entregasController.add(entregas);
            } catch (_) {}
          } else if (novaLista.length > _totalEntregasAntigo) {
            debugPrint('CHEGOU NOVO PEDIDO: quantidade anterior=${_totalEntregasAntigo} nova=${novaLista.length}');
            try {
              await _tocarSomSucesso();
            } catch (_) {}
            // Atualizar lista centralizada e contador dentro de setState
            if (!mounted) return;
            setState(() {
              entregas = List<dynamic>.from(novaLista);
              _atualizarContadores();
              _totalEntregasAntigo = novaLista.length;
            });
            // garantir que o StreamBuilder receba o novo valor imediatamente
            try {
              if (!_entregasController.isClosed) _entregasController.add(entregas);
            } catch (_) {}
            // rolar para o topo para mostrar o novo card
            try {
              if (_entregasScrollController.hasClients) {
                _entregasScrollController.animateTo(0.0,
                    duration: Duration(milliseconds: 400), curve: Curves.easeOut);
              }
            } catch (_) {}
            // Atualizar _lastEntregaId com o primeiro item, se existir
            final firstId = int.tryParse(novaLista.first['id'] ?? '') ?? 0;
            if (firstId > 0) _lastEntregaId = firstId;
          }
          debugPrint('STATUS REALTIME: polling (entregas)');
        } catch (e) {
          debugPrint('Erro no polling entregas: $e');
        }
      });
    } catch (e) {
      debugPrint('Erro ao iniciar polling de entregas: $e');
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Atualiza a lista de entregas de forma centralizada e notifica o stream
  void _setEntregas(List<dynamic> nova) {
    if (!mounted) return;
    setState(() => entregas = nova);
    _notifyEntregasDebounced(nova);
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

    // Parar qualquer som de fundo antes de abrir app externo/compartilhar
    try {
      await _pararAudio();
    } catch (e) {
      // ignorar
    }

    // Se existe foto, enviar via share_plus para permitir anexar arquivo (WhatsApp aceita via share)
    try {
      if (hasPhoto) {
        final f = File(imagemFalha!);
        if (await f.exists()) {
          // Anexar arquivo + texto usando share_plus
          // ignore: deprecated_member_use
          await Share.shareXFiles([XFile(f.path)], text: report);
        } else {
          // fallback para abrir apenas mensagem por link
          await _enviarWhatsApp(report, phone: numeroGestor);
        }
      } else {
        // sem foto: abrir WhatsApp com texto
        await _enviarWhatsApp(report, phone: numeroGestor);
      }
    } catch (e) {
      // ignorar falha no compartilhamento
    }

    setState(() {
      imagemFalha = null;
      motivoFalhaSelecionada = null;
    });

    // Remover localmente da lista de entregas para atualizar UI imediatamente
    // mover setState antes do fechamento do modal e comparar IDs como string
    if (mounted) {
      setState(() {
        _entregas.removeWhere(
          (item) => item['id'].toString() == cardId.toString(),
        );
        // Recalcula os contadores utilizados pelos mini-cards do cabeçalho
        _atualizarContadores();
      });
      // Notifica o stream para atualizar widgets que usam StreamBuilder
      _notifyEntregasDebounced(entregas);
      Navigator.of(context).pop();
    }

    // Se não há mais entregas, tocar som de rota concluída
    if (entregas.isEmpty) {
      try {
        await _tocarSomRotaConcluida();
      } catch (e) {
        // ignorar
      }
    }
  }

  Future<void> _salvarMapaSelecionado(String mapName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefSelectedMapKey, mapName);
    setState(() => _selectedMapName = mapName);
  }

  // Única função de modal: abre o bottom sheet de sucesso
  void _buildSuccessModal(BuildContext ctx, Map<String, dynamic> item) {
    final String nomeCliente = item['cliente'] ?? '';
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
                                        if (files.isNotEmpty) {
                                          // ignore: deprecated_member_use
                                          await Share.shareXFiles(
                                            files,
                                            text: mensagem,
                                          );
                                        } else {
                                          await _enviarWhatsApp(
                                            mensagem,
                                            phone: numeroGestor,
                                          );
                                        }
                                      } catch (e) {
                                        debugPrint(
                                          'Falha ao enviar mídia/mensagem: $e',
                                        );
                                      }

                                      // fechar modal e remover localmente
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
                                    if (m != null)
                                      debugPrint(
                                        'Coluna não encontrada no banco: ${m.group(1)}',
                                      );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '❌ Falha ao salvar no banco: ${err.split('\n').first}',
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
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

  Future<void> _abrirMapaComPreferencia(String endereco) async {
    final encoded = Uri.encodeComponent(endereco);
    final prefs = await SharedPreferences.getInstance();
    final sel = prefs.getString(prefSelectedMapKey) ?? '';

    // Tentar abrir esquema do app preferido
    Uri? uriToLaunch;

    if (sel.toLowerCase().contains('waze')) {
      uriToLaunch = Uri.parse('waze://?q=$encoded');
    } else if (sel.toLowerCase().contains('google') ||
        sel.toLowerCase().contains('maps')) {
      // usar esquema de navegação direta do Google Maps
      uriToLaunch = Uri.parse('google.navigation:q=$encoded');
    } else if (sel.isNotEmpty) {
      // fallback genérico: tentar mapa web com busca
      uriToLaunch = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$encoded',
      );
    } else {
      // sem preferência: tentar abrir primeiro app instalado ou fallback web
      final available = await MapLauncher.installedMaps;
      if (available.isNotEmpty) {
        final m = available.first;
        if (m.mapName.toLowerCase().contains('waze')) {
          uriToLaunch = Uri.parse('waze://?q=$encoded');
        } else if (m.mapName.toLowerCase().contains('google')) {
          uriToLaunch = Uri.parse('comgooglemaps://?q=$encoded');
        } else {
          uriToLaunch = Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=$encoded',
          );
        }
      } else {
        uriToLaunch = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$encoded',
        );
      }
    }

    // ignore: unnecessary_null_comparison
    if (uriToLaunch != null) {
      try {
        await launchUrl(uriToLaunch, mode: LaunchMode.externalApplication);
      } catch (_) {
        // fallback para web
        final web = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$encoded',
        );
        await launchUrl(web, mode: LaunchMode.externalApplication);
      }
    }
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
            entregas = lista;
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
      // Fazer query ordenando por `id` desc para trazer os pedidos mais recentes primeiro
      dynamic response = await r.retry(() async {
        return await Supabase.instance.client
            .from('entregas')
            .select('*')
            .or('status.eq.pendente,status.eq.em_rota')
            .order('id', ascending: false);
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
            // incluir 'status' para preservarmos o estado do item
            'status': m['status']?.toString() ?? '',
            // manter compatibilidade com chave antiga 'obs' e adicionar 'observacoes'
            'obs': m['obs']?.toString() ?? '',
            'observacoes':
                m['observacoes']?.toString() ??
                m['observacao']?.toString() ??
                m['obs']?.toString() ??
                '',
          };
        }).toList();

        // A lista já vem ordenada por id desc; atualizar estado substituindo a lista
        _setEntregas(List<dynamic>.from(lista));
        _atualizarContadores();
        setState(() {
          modoOffline = false;
          // Se ainda não inicializamos o contador antigo, setar para o tamanho atual
          if (_totalEntregasAntigo == -1) {
            _totalEntregasAntigo = lista.length;
          }
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
        imageQuality: 70,
      );
      return photo;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                        builder: (context) => IconButton(
                          icon: Icon(
                            Icons.menu,
                            color: modoDia ? Colors.black : Colors.white,
                          ),
                          onPressed: () => Scaffold.of(context).openEndDrawer(),
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
                    // Lado Direito: Balão de Chat com Badge Vermelho
                    Align(
                      alignment: Alignment.centerRight,
                      child: Stack(
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
                                atualizarAvisosNaoLidas: _atualizarAvisosNaoLidas,
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
      endDrawer: Drawer(
        backgroundColor: modoDia ? Colors.grey[100] : Colors.black,
        child: Column(
          children: [
            DrawerHeader(
              margin: EdgeInsets.zero,
              padding: EdgeInsets.zero,
              decoration: BoxDecoration(color: Colors.grey[900]),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.only(top: 18, bottom: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () async => _showAvatarPickerOptions(),
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          color: modoDia ? Colors.blue[200] : Colors.blue[700],
                          image: _avatarPath != null
                              ? DecorationImage(
                                  image: FileImage(File(_avatarPath!)),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _avatarPath == null
                            ? Icon(
                                Icons.person,
                                color: modoDia
                                    ? Colors.blue[900]
                                    : Colors.white,
                              )
                            : null,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      nomeMotorista,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.refresh,
                color: modoDia ? Colors.black87 : Colors.white70,
              ),
              title: Text(
                'Sincronizar Banco de Dados',
                style: TextStyle(color: modoDia ? Colors.black : Colors.white),
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
                style: TextStyle(color: modoDia ? Colors.black : Colors.white),
              ),
              trailing: modoDia ? Icon(Icons.check, color: Colors.green) : null,
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
                style: TextStyle(color: modoDia ? Colors.black : Colors.white),
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
                style: TextStyle(color: modoDia ? Colors.black : Colors.white),
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
                style: TextStyle(color: modoDia ? Colors.black : Colors.white),
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
                            color: modoDia ? Colors.black54 : Colors.white70,
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
                  final Color bg = modoDia ? Colors.white : Colors.grey[900]!;
                  final Color textColor = modoDia ? Colors.black : Colors.white;

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
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              try {
                                SystemNavigator.pop();
                              } catch (_) {
                                // fallback: nothing else to do here
                              }
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
      key: ValueKey(item["id"]),
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

                    SizedBox(height: 8),

                    // Mensagem do gestor (Post-it) com fundo amarelo
                    if ((item['obs'] ?? '').isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(10),
                        margin: EdgeInsets.only(top: 6, bottom: 6),
                        decoration: BoxDecoration(
                          color: Colors.yellow[600],
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black38,
                              blurRadius: 5,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.black,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item['obs'] ?? '',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    SizedBox(height: 8),

                    // LINHA DE BOTÕES
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: modoDia
                                  ? Colors.blue[400]!
                                  : Colors.blue[700]!,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 20,
                              ),
                              minimumSize: Size(80, 48),
                              textStyle: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () => _abrirMapaComPreferencia(
                              item['endereco'] ?? '',
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('ROTA'),
                            ),
                          ),
                        ),

                        SizedBox(width: 8),

                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: modoDia
                                  ? Colors.red[300]!
                                  : Colors.red[700]!,
                              foregroundColor: modoDia
                                  ? Colors.black
                                  : Colors.white,
                              padding: EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 20,
                              ),
                              minimumSize: Size(80, 48),
                              textStyle: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () {
                              final TextEditingController
                              motivoOutrosController = TextEditingController();
                              final motivos = [
                                'Cliente Ausente',
                                'Endereço Incorreto',
                                'Recusado',
                                'Danos',
                                'Tentativa Frustrada',
                                'Documento Ausente',
                                'Outros Motivos',
                                'Sem Acesso',
                              ];

                              // Reset imagemFalha e motivo ao abrir o modal (garantia explícita)
                              setState(() {
                                imagemFalha = null;
                                motivoFalhaSelecionada = null;
                              });

                              // Tocar som de falha ao abrir o modal
                              _tocarSomFalha();

                              showDialog(
                                context: context,
                                builder: (ctx) {
                                  return StatefulBuilder(
                                    builder: (ctx2, setStateDialog) {
                                      XFile? pickedImageLocal =
                                          imagemFalha != null
                                          ? XFile(imagemFalha!)
                                          : null;
                                      String? motivoSelecionadoLocal =
                                          motivoFalhaSelecionada;

                                      final String pickedPath =
                                          pickedImageLocal?.path ?? '';

                                      final Color bg = modoDia
                                          ? Colors.white
                                          : Colors.grey[900]!;
                                      final Color textColor = modoDia
                                          ? Colors.black87
                                          : Colors.white;
                                      final Color secondary = modoDia
                                          ? Colors.black54
                                          : Colors.white70;

                                      return AlertDialog(
                                        backgroundColor: bg,
                                        title: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Relatar Falha',
                                              style: TextStyle(
                                                color: textColor,
                                              ),
                                            ),
                                            IconButton(
                                              icon: Icon(
                                                Icons.camera_alt,
                                                color: textColor,
                                              ),
                                              onPressed: () async {
                                                // centraliza a captura em _tirarFoto()
                                                final XFile? photo =
                                                    await _tirarFoto();
                                                if (photo != null) {
                                                  setState(() {
                                                    imagemFalha = photo.path;
                                                  });
                                                  setStateDialog(
                                                    () => pickedImageLocal =
                                                        photo,
                                                  );
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                        content: SingleChildScrollView(
                                          child: SizedBox(
                                            width:
                                                MediaQuery.of(
                                                  context,
                                                ).size.width *
                                                0.9,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                // Espaço da Foto (Topo)
                                                Center(
                                                  child: Container(
                                                    width: 96,
                                                    height: 96,
                                                    margin: EdgeInsets.only(
                                                      bottom: 12,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      color: modoDia
                                                          ? Colors.grey[100]
                                                          : Colors.grey[850],
                                                      image:
                                                          pickedImageLocal !=
                                                              null
                                                          ? DecorationImage(
                                                              image: FileImage(
                                                                File(
                                                                  pickedPath,
                                                                ),
                                                              ),
                                                              fit: BoxFit.cover,
                                                            )
                                                          : null,
                                                    ),
                                                    child:
                                                        pickedImageLocal == null
                                                        ? Icon(
                                                            Icons.camera_alt,
                                                            color: secondary,
                                                            size: 36,
                                                          )
                                                        : null,
                                                  ),
                                                ),

                                                // Seletor de Motivos
                                                GridView.count(
                                                  crossAxisCount: 2,
                                                  mainAxisSpacing: 10,
                                                  crossAxisSpacing: 10,
                                                  childAspectRatio: 2.1,
                                                  shrinkWrap: true,
                                                  physics:
                                                      NeverScrollableScrollPhysics(),
                                                  children: motivos.map((
                                                    motivo,
                                                  ) {
                                                    final bool isSel =
                                                        motivoSelecionadoLocal ==
                                                        motivo;
                                                    return ElevatedButton(
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: isSel
                                                            ? Colors.red
                                                            : Colors.grey[800],
                                                        foregroundColor:
                                                            Colors.white,
                                                        padding:
                                                            EdgeInsets.symmetric(
                                                              vertical: 12,
                                                            ),
                                                      ),
                                                      onPressed: () {
                                                        setStateDialog(
                                                          () =>
                                                              motivoSelecionadoLocal =
                                                                  motivo,
                                                        );
                                                        // atualizar também no estado pai para rastreio/reatividade
                                                        setState(
                                                          () =>
                                                              motivoFalhaSelecionada =
                                                                  motivo,
                                                        );
                                                      },
                                                      child: Padding(
                                                        padding:
                                                            EdgeInsets.symmetric(
                                                              horizontal: 4,
                                                            ),
                                                        child: Text(
                                                          motivo,
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            height: 1.1,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),

                                                SizedBox(height: 12),
                                                TextField(
                                                  controller:
                                                      motivoOutrosController,
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                  decoration: InputDecoration(
                                                    hintText:
                                                        'Detalhes (opcional)',
                                                    hintStyle: TextStyle(
                                                      color: Colors.white54,
                                                    ),
                                                    filled: true,
                                                    fillColor: Colors.grey[800],
                                                  ),
                                                ),
                                                SizedBox(height: 12),

                                                SizedBox(height: 8),

                                                // Substituído o botão de foto pelo botão de envio
                                                // O botão permanece travado até que um motivo seja selecionado
                                                SizedBox(
                                                  width: double.infinity,
                                                  child: ElevatedButton(
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                          (motivoSelecionadoLocal !=
                                                              null)
                                                          ? Colors.red
                                                          : Colors.grey[700],
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                            vertical: 16,
                                                          ),
                                                      textStyle: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    onPressed:
                                                        (motivoSelecionadoLocal !=
                                                            null)
                                                        ? () async {
                                                            final detalhesController =
                                                                motivoOutrosController;
                                                            final detalhesText =
                                                                detalhesController
                                                                    .text
                                                                    .trim();

                                                            final motivoFinal =
                                                                motivoSelecionadoLocal ??
                                                                'Não informado';

                                                            final card =
                                                                entregas[index];
                                                            try {
                                                              try {
                                                                await _audioPlayer
                                                                    .setVolume(
                                                                      1.0,
                                                                    );
                                                                await _audioPlayer.play(
                                                                  AssetSource(
                                                                    'audios/falha_3.mp3',
                                                                  ),
                                                                );
                                                              } catch (_) {}
                                                              await Future.delayed(
                                                                Duration(
                                                                  milliseconds:
                                                                      500,
                                                                ),
                                                              );
                                                            } catch (_) {}

                                                            // Primeiro, tentar atualizar no Supabase
                                                            final payload = {
                                                              'motivo_nao_entrega':
                                                                  motivoFinal,
                                                              'obs':
                                                                  detalhesText,
                                                              'data_conclusao':
                                                                  DateTime.now()
                                                                      .toIso8601String(),
                                                              'status': 'falha',
                                                            };

                                                            dynamic res;
                                                            try {
                                                              res = await Supabase
                                                                  .instance
                                                                  .client
                                                                  .from(
                                                                    'entregas',
                                                                  )
                                                                  .update(
                                                                    payload,
                                                                  )
                                                                  .eq(
                                                                    'id',
                                                                    card['id'],
                                                                  )
                                                                  .select();
                                                            } catch (err) {
                                                              debugPrint(
                                                                'ERRO NO UPDATE FALHA: $err',
                                                              );
                                                              if (mounted) {
                                                                ScaffoldMessenger.of(
                                                                  context,
                                                                ).showSnackBar(
                                                                  SnackBar(
                                                                    content: Text(
                                                                      'Falha ao salvar motivo no servidor.',
                                                                    ),
                                                                  ),
                                                                );
                                                              }
                                                              return;
                                                            }

                                                            // Se update OK, proceder com envio/remoção local
                                                            if (res is List &&
                                                                res.isNotEmpty) {
                                                              await _enviarFalha(
                                                                card['id'] ??
                                                                    '',
                                                                card['cliente'] ??
                                                                    '',
                                                                card['endereco'] ??
                                                                    '',
                                                                motivoFinal,
                                                                detalhesText,
                                                              );

                                                              // remover localmente após persistência
                                                              setState(() {
                                                                entregas.removeWhere(
                                                                  (c) =>
                                                                      c['id'] ==
                                                                      card['id'],
                                                                );
                                                              });
                                                              // Notificar stream/UI que a lista mudou
                                                              _notifyEntregasDebounced(
                                                                List<
                                                                  dynamic
                                                                >.from(
                                                                  entregas,
                                                                ),
                                                              );
                                                            } else {
                                                              if (mounted) {
                                                                ScaffoldMessenger.of(
                                                                  context,
                                                                ).showSnackBar(
                                                                  SnackBar(
                                                                    content: Text(
                                                                      'Atualização não confirmada pelo servidor.',
                                                                    ),
                                                                  ),
                                                                );
                                                              }
                                                            }
                                                          }
                                                        : null,
                                                    child: Text(
                                                      'ENVIAR NOTIFICAÇÃO',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: modoDia
                                                            ? FontWeight.bold
                                                            : FontWeight.normal,
                                                      ),
                                                    ),
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
                            },
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('FALHA'),
                            ),
                          ),
                        ),

                        SizedBox(width: 8),

                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: modoDia
                                  ? Colors.green[400]!
                                  : Colors.green[700]!,
                              foregroundColor: modoDia
                                  ? Colors.black
                                  : Colors.white,
                              padding: EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 20,
                              ),
                              minimumSize: Size(80, 48),
                              textStyle: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () => _buildSuccessModal(
                              context,
                              Map<String, dynamic>.from(item),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('OK'),
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
