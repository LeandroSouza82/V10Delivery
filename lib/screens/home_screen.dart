import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
// map_launcher and url_launcher removed from Home UI (no external links/Lottie)
import 'package:intl/intl.dart';
// removed broken project-specific core imports; using local fallbacks below
// location_service import removed from Home UI (not used here)
// supabase import not required in this file now (drawer handles auth operations)
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:v10_delivery/services/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';
// removed widget imports that are not present in this workspace
// provide minimal local placeholders and use default Flutter styles/colors
import 'package:v10_delivery/splash_page.dart';

// Local placeholders and style fallbacks
class AppSpacing {
  static const double s8 = 8.0;
  static const double s12 = 12.0;
  static const double s16 = 16.0;
  static const double s20 = 16.0;
}

class AppRadius {
  static BorderRadius get modalTop => BorderRadius.circular(12);
}

class AppStyles {
  static const TextStyle modalTitle = TextStyle(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.bold,
  );
  static const TextStyle white70 = TextStyle(color: Colors.white70);
  static const TextStyle chipLabelWhite = TextStyle(color: Colors.white);
  static const TextStyle inputTextWhite = TextStyle(color: Colors.white);
}

class AppColors {
  static const Color background = Colors.blue;
}

class DashboardStats extends StatelessWidget {
  final List<Map<String, dynamic>>? entregas;
  final String? selectedFilter;
  final ValueChanged<String>? onFilterChanged;

  const DashboardStats({
    super.key,
    this.entregas,
    this.selectedFilter,
    this.onFilterChanged,
  });
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class DeliveryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final int? index;
  final Function? onConfirmDelivery;
  final Function? onReportFailure;

  const DeliveryCard({
    super.key,
    required this.data,
    this.index,
    this.onConfirmDelivery,
    this.onReportFailure,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(data['cliente'] ?? ''),
    subtitle: Text(data['endereco'] ?? ''),
  );
}

class FailureConfirmationModal extends StatelessWidget {
  const FailureConfirmationModal({super.key});
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Falha'),
    content: const Text('Confirmação de falha.'),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('OK'),
      ),
    ],
  );

  // Exposição de helper show para compatibilidade com chamadas existentes
  static Future<Map<String, String>?> show(
    BuildContext context, {
    String? cliente,
    String? endereco,
  }) async {
    String motivo = '';
    final TextEditingController ctrl = TextEditingController();
    final res = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Confirmar Falha'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (cliente != null) Text('Cliente: $cliente'),
              if (endereco != null) Text('Endereço: $endereco'),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(labelText: 'Motivo'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                motivo = ctrl.text.trim();
                Navigator.of(ctx).pop({'motivo': motivo});
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    return res;
  }
}

class RotaMotorista extends StatefulWidget {
  const RotaMotorista({super.key});

  @override
  RotaMotoristaState createState() => RotaMotoristaState();
}

// Backwards-compatible alias: some older files/routes reference `HomeScreen`.
// Keep this thin wrapper so callers can use `HomeScreen()` without renaming
// the existing implementation.
class HomeScreen extends RotaMotorista {
  const HomeScreen({super.key});
}

class RotaMotoristaState extends State<RotaMotorista>
    with SingleTickerProviderStateMixin {
  final String nomeMotorista = "LEANDRO";
  String? caminhoFotoSession;
  XFile? fotoEvidencia;
  late AnimationController _buscarController;
  bool modoDia = false;

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _searchingActive = false;
  bool _awaitStartChama = false;
  // Location service instantiation removed from Home state (no appbar control).

  // Scaffold key to safely control drawers/modals without using Scaffold.of(context)
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Número do gestor para envio de mensagens (WhatsApp)
  String numeroGestor = '55119XXXXXXXX';

  // Função utilitária local para enviar WhatsApp (usa url_launcher)
  Future<void> enviarWhatsApp(String mensagem, {String? phone}) async {
    try {
      final String phoneRaw = (phone ?? numeroGestor)
          .replaceAll('+', '')
          .replaceAll(' ', '');
      final String encoded = Uri.encodeComponent(mensagem);
      final Uri native = Uri.parse(
        'whatsapp://send?phone=$phoneRaw&text=$encoded',
      );
      final Uri web = Uri.parse(
        'https://api.whatsapp.com/send?phone=$phoneRaw&text=$encoded',
      );
      if (await canLaunchUrl(native)) {
        await launchUrl(native, mode: LaunchMode.externalApplication);
        return;
      }
      await launchUrl(web, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Erro ao abrir WhatsApp (local): $e');
    }
  }

  // Realtime controller and channel for entregas
  StreamController<List<Map<String, dynamic>>>? _entregasController;
  dynamic _entregasChannel;
  int _lastEntregasCount = 0;
  // Heartbeat timer to keep driver online independently
  Timer? _heartbeatTimer;

  List<Map<String, String>> entregas = [
    {
      "id": "01",
      "cliente": "JOÃO SILVA",
      "endereco": "Rua Montenegro, 150",
      "tipo": "entrega",
      "obs": "Interfone com defeito.",
    },
    {
      "id": "02",
      "cliente": "MARIA OLIVEIRA",
      "endereco": "Av. dos Coqueiros, 890",
      "tipo": "recolha",
      "obs": "Cuidado com o cachorro.",
    },
    {
      "id": "03",
      "cliente": "LOGÍSTICA V10",
      "endereco": "Galpão Central",
      "tipo": "outros",
      "obs": "Retirar pacotes da tarde.",
    },
  ];

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

  String? imagemFalha;
  String? motivoFalhaSelecionada;
  int entregasFaltam = 0;
  int recolhasFaltam = 0;
  int outrosFaltam = 0;
  String? _selectedMapName;
  String _filtroSelecionado = 'TODOS';
  bool _permissionDialogShown = false;

  @override
  void initState() {
    super.initState();
    _atualizarContadores();

    // manter a tela ligada enquanto o motorista usa a tela de rota
    try {
      WakelockPlus.enable();
    } catch (e) {
      debugPrint('Wakelock enable falhou: $e');
    }

    _buscarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _audioPlayer.onPlayerComplete.listen((event) {
      if (_awaitStartChama) {
        _awaitStartChama = false;
        if (_searchingActive) {
          _startChamaLoop();
        }
      }
    });

    try {
      _audioPlayer.setReleaseMode(ReleaseMode.stop);
      _audioPlayer.setVolume(1.0);
    } catch (e) {
      debugPrint(e.toString());
    }

    SharedPreferences.getInstance().then((prefs) {
      final mapName = prefs.getString('selected_map_app');
      if (mapName != null && mapName.isNotEmpty) {
        setState(() => _selectedMapName = mapName);
      }
    });

    // initialize realtime entregas stream
    _entregasController =
        StreamController<List<Map<String, dynamic>>>.broadcast();
    _initEntregasRealtime();

    // Start independent heartbeat if prefs indicate we're online
    SharedPreferences.getInstance().then((prefs) {
      final wasOnline = prefs.getBool('is_online') ?? false;
      if (wasOnline) _startHeartbeat();
    });

    // show permission dialog once after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_permissionDialogShown) {
        _permissionDialogShown = true;
        _showPermissionDialog();
      }
    });
  }

  @override
  void dispose() {
    // restaurar comportamento de economia de energia
    try {
      WakelockPlus.disable();
    } catch (e) {
      debugPrint('Wakelock disable falhou: $e');
    }

    _buscarController.dispose();
    _audioPlayer.dispose();
    _nomeController.dispose();
    _aptController.dispose();
    try {
      if (_entregasChannel != null) {
        try {
          _entregasChannel.unsubscribe();
        } catch (_) {}
      }
    } catch (_) {}
    try {
      _entregasController?.close();
    } catch (_) {}
    try {
      _heartbeatTimer?.cancel();
    } catch (_) {}
    super.dispose();
  }

  // Heartbeat control: independent Timer every 15s
  void _startHeartbeat() {
    try {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        atualizarSinalOnline();
      });
      // send immediate pulse
      atualizarSinalOnline();
      debugPrint('HomeScreen: heartbeat iniciado');
    } catch (e) {
      debugPrint('Erro iniciando heartbeat: $e');
    }
  }

  // ignore: unused_element
  void _stopHeartbeat() {
    try {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      debugPrint('HomeScreen: heartbeat parado');
    } catch (e) {
      debugPrint('Erro parando heartbeat: $e');
    }
  }

  // Atualiza sinal online no Supabase para o ID fixo solicitado
  Future<void> atualizarSinalOnline() async {
    try {
      const String heartbeatId = '447bb6e6-2086-421b-9e49-00c0d8d1c2c8';
      final nowIso = DateTime.now().toUtc().toIso8601String();
      await Supabase.instance.client
          .from('motoristas')
          .update({'esta_online': true, 'ultima_atualizacao': nowIso})
          .eq('id', heartbeatId);
      debugPrint('atualizarSinalOnline enviado para $heartbeatId @ $nowIso');
    } catch (e) {
      debugPrint('Erro atualizarSinalOnline: $e');
    }
  }

  void _atualizarContadores() {
    entregasFaltam = 0;
    recolhasFaltam = 0;
    outrosFaltam = 0;
    for (final e in entregas) {
      final tipo = (e['tipo'] ?? '').toLowerCase();
      if (tipo.contains('entrega')) {
        entregasFaltam++;
      } else if (tipo.contains('recolha')) {
        recolhasFaltam++;
      } else {
        outrosFaltam++;
      }
    }
  }

  // ignore: unused_element
  Future<void> _tocarSomFalha() async {
    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('audios/falha_3.mp3'));
      Future.delayed(const Duration(seconds: 3), () async {
        try {
          await _audioPlayer.stop();
        } catch (e) {
          debugPrint(e.toString());
        }
      });
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _tocarSomSucesso() async {
    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('audios/sucesso.mp3'));
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _tocarSomRotaConcluida() async {
    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('audios/final.mp3'));
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _startChamaLoop() async {
    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.stop();
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('audios/chama.mp3'));
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _pararAudio() async {
    try {
      _awaitStartChama = false;
      await _audioPlayer.stop();
      try {
        await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      } catch (e) {
        debugPrint(e.toString());
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  // ignore: unused_element
  Future<void> _enviarFalha(
    String cardId,
    String cliente,
    String endereco,
    String motivoFinal,
  ) async {
    // Nota: envio do WhatsApp agora é tratado pelo FailureConfirmationModal.
    try {
      await _pararAudio();
    } catch (e) {
      debugPrint(e.toString());
    }

    setState(() {
      entregas.removeWhere((c) => c['id'] == cardId);
      imagemFalha = null;
      motivoFalhaSelecionada = null;
    });

    if (entregas.isEmpty) {
      setState(() => _searchingActive = false);
      try {
        await _tocarSomRotaConcluida();
      } catch (e) {
        debugPrint(e.toString());
      }
    }

    if (!mounted) return;
    final navigator = Navigator.of(context);
    navigator.pop();
  }

  Future<void> _showPermissionDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Row(
            children: const [
              Icon(Icons.security, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Permissões Necessárias para Entregas',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          content: const Text(
            "Para garantir que você receba novas rotas e que seu trajeto seja registrado corretamente, precisamos que você libere: 1. Localização 'Sempre'; 2. Início Automático; 3. Sem restrições de Bateria.",
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.of(ctx).pop();
                // Request location permission
                try {
                  final status = await Geolocator.checkPermission();
                  if (status == LocationPermission.always) {
                    // already good
                  } else {
                    final req = await Geolocator.requestPermission();
                    if (req == LocationPermission.denied) {
                      await Geolocator.openAppSettings();
                    } else if (req == LocationPermission.deniedForever) {
                      await Geolocator.openAppSettings();
                    } else if (req == LocationPermission.unableToDetermine) {
                      await Geolocator.openLocationSettings();
                    }
                  }
                } catch (e) {
                  debugPrint('Erro pedindo permissão de localização: $e');
                }

                try {
                  await Geolocator.openLocationSettings();
                } catch (_) {}

                _startForegroundService();
              },
              child: const Text('CONFIGURAR'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK / ENTENDI'),
            ),
          ],
        );
      },
    );
  }

  void _startForegroundService() {
    // Placeholder: foreground service integration can be added here
    // using flutter_foreground_task or platform channels.
    debugPrint('startForegroundService: stub called');
  }

  Future<List<Map<String, dynamic>>> _fetchEntregasForDriver(
    String idLogado,
  ) async {
    try {
      var builder = Supabase.instance.client.from('entregas').select();
      builder = builder.eq('motorista_id', idLogado as Object);
      if (_filtroSelecionado != 'TODOS') {
        builder = builder.eq('tipo', _filtroSelecionado as Object);
      }
      // active statuses
      builder = builder.or('status.eq.pendente,status.eq.em_rota');

      final dynamic resp = await builder.order(
        'ordem_logistica',
        ascending: true,
      );
      final raw = resp as List<dynamic>? ?? <dynamic>[];
      return raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    } catch (e) {
      debugPrint('Erro fetching entregas: $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _initEntregasRealtime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final idLogado =
          prefs.getString('driver_uuid') ??
          Supabase.instance.client.auth.currentUser?.id;
      if (idLogado == null) {
        _entregasController?.add(<Map<String, dynamic>>[]);
        return;
      }

      // initial fetch
      final initial = await _fetchEntregasForDriver(idLogado);
      _entregasController?.add(initial);

      // subscribe to realtime changes for entregas filtered by motorista_id
      try {
        final dynamic client = Supabase.instance.client;
        _entregasChannel = client.channel('public:entregas').on(
          'postgres_changes',
          {
            'event': '*',
            'schema': 'public',
            'table': 'entregas',
            'filter': 'motorista_id=eq.$idLogado',
          },
          (payload, [ref]) async {
            final next = await _fetchEntregasForDriver(idLogado);
            if (_entregasController != null && !_entregasController!.isClosed) {
              _entregasController!.add(next);
            }
          },
        ).subscribe();
      } catch (e) {
        debugPrint('Realtime subscription failed, falling back to polling: $e');
        // fallback: periodic polling
        Timer.periodic(const Duration(seconds: 3), (t) async {
          if (_entregasController == null || _entregasController!.isClosed) {
            t.cancel();
            return;
          }
          final next = await _fetchEntregasForDriver(idLogado);
          if (!_entregasController!.isClosed) _entregasController!.add(next);
        });
      }
    } catch (e) {
      debugPrint('Erro initEntregasRealtime: $e');
      _entregasController?.add(<Map<String, dynamic>>[]);
    }
  }

  // Map selection persistence removed from Home UI.

  // ignore: unused_element
  void _buildSuccessModal(BuildContext ctx, String nomeCliente) {
    String? opcaoSelecionada;
    String obsTexto = '';

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.blueGrey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 16.0,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16.0,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'CONFIRMAR ENTREGA',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12.0),
                    Text(
                      'Como foi entregue? (selecione uma opção)',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12.0),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _opcoesEntrega.map((opcao) {
                        final selected = opcaoSelecionada == opcao;
                        return ChoiceChip(
                          label: Text(opcao),
                          selected: selected,
                          onSelected: (sel) => setModalState(() {
                            opcaoSelecionada = sel ? opcao : null;
                          }),
                          selectedColor: Colors.blueGrey[700],
                          backgroundColor: Colors.white10,
                          labelStyle: const TextStyle(color: Colors.white),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12.0),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Observações (opcional)',
                        filled: true,
                        fillColor: Colors.white10,
                        border: const OutlineInputBorder(),
                        labelStyle: const TextStyle(color: Colors.white70),
                      ),
                      style: const TextStyle(color: Colors.white),
                      onChanged: (v) => obsTexto = v,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16.0),
                    ElevatedButton(
                      onPressed: opcaoSelecionada == null
                          ? null
                          : () async {
                              final navigator = Navigator.of(ctx);
                              await _audioPlayer.stop();
                              await _tocarSomSucesso();
                              await Future.delayed(
                                const Duration(milliseconds: 500),
                              );

                              final hora = DateFormat(
                                'HH:mm',
                              ).format(DateTime.now());
                              final mensagem =
                                  '📦 ENTREGA: $nomeCliente\nStatus: $opcaoSelecionada\nObservações: ${obsTexto.isNotEmpty ? obsTexto : '-'}\nMotorista: $nomeMotorista\nHora: $hora';

                              try {
                                try {
                                  await _audioPlayer.setVolume(1.0);
                                  await _audioPlayer.play(
                                    AssetSource('audios/sucesso.mp3'),
                                  );
                                } catch (e) {
                                  debugPrint(e.toString());
                                }
                                await Future.delayed(
                                  const Duration(milliseconds: 500),
                                );
                                try {
                                  await enviarWhatsApp(
                                    mensagem,
                                    phone: numeroGestor,
                                  );
                                } catch (e) {
                                  debugPrint(e.toString());
                                }
                              } catch (e) {
                                debugPrint(e.toString());
                              }

                              final idx = entregas.indexWhere(
                                (e) => (e['cliente'] ?? '') == nomeCliente,
                              );
                              if (idx != -1) {
                                setState(() {
                                  entregas.removeAt(idx);
                                  _atualizarContadores();
                                });
                              }

                              if (entregas.isEmpty) {
                                try {
                                  await _tocarSomRotaConcluida();
                                } catch (e) {
                                  debugPrint(e.toString());
                                }
                              }

                              if (!mounted) return;
                              navigator.pop();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 52),
                      ),
                      child: const Text('ENVIAR PARA GESTOR'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Map launching removed from Home UI to avoid external links and Lottie usage.

  // Map preference UI removed — handled externally or via settings.

  @override
  Widget build(BuildContext context) {
    // Minimal placeholder UI to keep the screen functional after migration.
    return Scaffold(
      backgroundColor: Colors.blue,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        centerTitle: true,
        leadingWidth: 72,
        leading: FutureBuilder<List<Map<String, dynamic>>>(
          future: NotificationService.fetchAvisos(),
          builder: (ctx, snap) {
            final avisos = snap.data ?? <Map<String, dynamic>>[];
            final count = avisos
                .where(
                  (a) =>
                      a['lida'] == false || a['lida'] == 0 || a['lida'] == 'f',
                )
                .length;
            return IconButton(
              tooltip: 'Avisos do Gestor',
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.chat),
                  if (count > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          count.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              onPressed: () {
                if (snap.connectionState == ConnectionState.waiting) return;
                final avisosLocal = avisos;
                showDialog<void>(
                  context: context,
                  builder: (dctx) {
                    return AlertDialog(
                      title: const Text('Avisos do Gestor'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: avisosLocal.isEmpty
                            ? const Text('Nenhum aviso encontrado')
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: avisosLocal.length,
                                itemBuilder: (c, i) {
                                  final a = avisosLocal[i];
                                  final texto =
                                      a['texto'] ??
                                      a['conteudo'] ??
                                      a['mensagem'] ??
                                      a['titulo'] ??
                                      '';
                                  final lida =
                                      a['lida'] == true ||
                                      a['lida'] == 1 ||
                                      a['lida'] == 't';
                                  return ListTile(
                                    title: Text(texto.toString()),
                                    subtitle: lida
                                        ? const Text('Lida')
                                        : const Text('Não lida'),
                                  );
                                },
                              ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dctx).pop(),
                          child: const Text('Fechar'),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
        title: GestureDetector(
          // developer shortcut: long-press to insert a test entrega for the logged-in driver
          onLongPress: _insertTestEntrega,
          child: const Text(
            'V10 Delivery',
            style: TextStyle(color: Colors.white),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu),
            onPressed: _showMenuModal,
          ),
        ],
      ),
      key: _scaffoldKey,
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Mapa selecionado: ${_selectedMapName ?? 'padrão'}",
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),

            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _entregasController?.stream,
                builder: (ctx, snap) {
                  final lista = snap.data ?? <Map<String, dynamic>>[];

                  // Áudio: tocar 'chama' quando houver aumento na quantidade de entregas
                  try {
                    final current = lista.length;
                    if (current > _lastEntregasCount) {
                      // novo item adicionado — tocar uma vez por incremento
                      try {
                        _audioPlayer.play(AssetSource('audios/chama.mp3'));
                      } catch (e) {
                        debugPrint('Erro ao tocar chama.mp3: $e');
                      }
                    }
                    _lastEntregasCount = current;
                  } catch (_) {}

                  // counts are computed inside DashboardStats using the provided lista

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DashboardStats(
                        entregas: lista,
                        selectedFilter: _filtroSelecionado,
                        onFilterChanged: (f) {
                          setState(() {
                            if (_filtroSelecionado == f) {
                              _filtroSelecionado = 'TODOS';
                            } else {
                              _filtroSelecionado = f;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child:
                            (snap.connectionState == ConnectionState.waiting ||
                                lista.isEmpty)
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    SizedBox(
                                      width: 80,
                                      height: 80,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.deepPurple,
                                            ),
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'Buscando rotas na sua região...',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: lista.length,
                                itemBuilder: (ctx, idx) {
                                  final e = lista[idx];
                                  return DeliveryCard(
                                    key: ValueKey(e['id']),
                                    data: Map<String, dynamic>.from(e),
                                    index: idx,
                                    onConfirmDelivery: (ctx, clienteNome) {
                                      _finalizarEntrega(e, ctx, clienteNome);
                                    },
                                    onReportFailure: (id, cliente, endereco, motivo) async {
                                      final messenger = ScaffoldMessenger.of(
                                        ctx,
                                      );
                                      final idEnt = id.toString();
                                      if (idEnt.isEmpty) {
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'ID da entrega inválido',
                                            ),
                                          ),
                                        );
                                        return;
                                      }

                                      // open the failure modal to collect reason/obs
                                      final Map<String, String>? result =
                                          await FailureConfirmationModal.show(
                                            ctx,
                                            cliente: cliente.toString(),
                                            endereco: endereco.toString(),
                                          );

                                      if (result == null ||
                                          (result['motivo'] ?? '').isEmpty) {
                                        // user cancelled or didn't choose a reason
                                        return;
                                      }

                                      final motivoDigitado = result['motivo']!
                                          .toString();

                                      try {
                                        final now = DateTime.now();

                                        final payloadFalha = {
                                          'status': 'falha',
                                          'motivo_nao_entrega': motivoDigitado,
                                          'data_conclusao': now
                                              .toUtc()
                                              .toIso8601String(),
                                          'horario_conclusao': now
                                              .toUtc()
                                              .toIso8601String(),
                                        };

                                        debugPrint(
                                          '[DEBUG] entregas.update payload (falha) id=$idEnt: $payloadFalha',
                                        );

                                        final updateResultFalha = await Supabase
                                            .instance
                                            .client
                                            .from('entregas')
                                            .update(payloadFalha)
                                            .eq('id', idEnt);

                                        debugPrint(
                                          '[DEBUG] entregas.update result (falha) id=$idEnt: $updateResultFalha',
                                        );

                                        // notify gestor after successful update (formatted V10)
                                        final phone =
                                            await _getTelefoneGestor();
                                        final hora = DateFormat(
                                          'HH:mm',
                                        ).format(DateTime.now());
                                        final entregador =
                                            nomeMotorista.isNotEmpty
                                            ? nomeMotorista
                                            : 'Leandro';
                                        final mensagem = StringBuffer()
                                          ..writeln(
                                            '⚠️ *FALHA NA ENTREGA - V10 Delivery*',
                                          )
                                          ..writeln('🕒 *Horário:* $hora')
                                          ..writeln(
                                            '👤 *Cliente:* ${cliente.toString()}',
                                          )
                                          ..writeln(
                                            '📍 *Endereço:* ${endereco.toString()}',
                                          )
                                          ..writeln('🤝 *Recebido por:* -')
                                          ..writeln(
                                            '🚚 *Entregador:* $entregador',
                                          )
                                          ..writeln(
                                            '📝 *Obs:* ${motivoDigitado.isNotEmpty ? motivoDigitado : '-'}',
                                          );

                                        try {
                                          await enviarWhatsApp(
                                            mensagem.toString(),
                                            phone: phone,
                                          );
                                        } catch (_) {
                                          final uri = Uri(
                                            scheme: 'tel',
                                            path: phone,
                                          );
                                          if (await canLaunchUrl(uri)) {
                                            await launchUrl(uri);
                                          }
                                        }

                                        // Após atualizar como 'falha', buscar lista atual e tocar som de sucesso se vazia
                                        try {
                                          final prefs =
                                              await SharedPreferences.getInstance();
                                          final idLogado =
                                              prefs.getString('driver_uuid') ??
                                              Supabase
                                                  .instance
                                                  .client
                                                  .auth
                                                  .currentUser
                                                  ?.id;
                                          if (idLogado != null) {
                                            final next =
                                                await _fetchEntregasForDriver(
                                                  idLogado,
                                                );
                                            if (next.isEmpty) {
                                              try {
                                                await _tocarSomSucesso();
                                              } catch (e) {
                                                debugPrint(
                                                  'Erro ao tocar som de sucesso: $e',
                                                );
                                              }
                                            }
                                          }
                                        } catch (e) {
                                          debugPrint(
                                            'Erro verificando entregas após falha: $e',
                                          );
                                        }
                                      } catch (e) {
                                        debugPrint('Erro ao marcar falha: $e');
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Erro ao registrar falha: ${e.toString()}',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ), // Expanded
          ], // Column children
        ), // Column
      ), // Padding
    ); // Scaffold
  }

  // Helpers: fetch driver name, greeting and menu modal
  Future<String> _getDriverName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('driver_name');
      if (saved != null && saved.isNotEmpty) return saved;

      final uuid = prefs.getString('driver_uuid');
      if (uuid != null && uuid.isNotEmpty) {
        try {
          final resp = await Supabase.instance.client
              .from('motoristas')
              .select('nome')
              .eq('uuid', uuid)
              .limit(1)
              .maybeSingle();
          final mapResp = resp as Map<dynamic, dynamic>?;
          if (mapResp != null && mapResp['nome'] != null) {
            final n = mapResp['nome'].toString();
            if (n.isNotEmpty) {
              await prefs.setString('driver_name', n);
              return n;
            }
          }
        } catch (_) {}
      }

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final meta = user.userMetadata ?? <String, dynamic>{};
        final nomeMeta = meta['nome'] ?? meta['name'] ?? meta['full_name'];
        if (nomeMeta != null && nomeMeta.toString().isNotEmpty) {
          return nomeMeta.toString();
        }
      }
    } catch (_) {}
    return 'Motorista';
  }

  Future<String> _getTelefoneGestor() async {
    try {
      final dynamic q = await Supabase.instance.client
          .from('config_geral')
          .select('telefone_gestor')
          .limit(1)
          .maybeSingle();
      if (q != null) {
        final map = q as Map<dynamic, dynamic>;
        final val = map['telefone_gestor'] ?? map['telefone'] ?? map['contato'];
        if (val != null && val.toString().isNotEmpty) {
          return val.toString();
        }
      }
    } catch (_) {}
    try {
      return numeroGestor;
    } catch (_) {}
    return '5548996525008';
  }

  Future<void> _finalizarEntrega(
    Map<String, dynamic> entrega,
    BuildContext ctx,
    String clienteNome,
  ) async {
    debugPrint('>>> DISPARANDO GRAVAÇÃO DO OK <<<');
    final messenger = ScaffoldMessenger.of(ctx);
    final idEnt = entrega['id']?.toString() ?? '';
    if (idEnt.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('ID da entrega inválido')),
      );
      return;
    }
    try {
      final now = DateTime.now();
      final hora = DateFormat('HH:mm').format(now);

      final payloadOk = {
        'status': 'entregue',
        'data_conclusao': now.toUtc().toIso8601String(),
        'horario_conclusao': now.toUtc().toIso8601String(),
      };

      final dados = payloadOk;
      debugPrint('[DEBUG] OK Payload: $dados');

      debugPrint(
        '[DEBUG] entregas.update payload (entregue) id=$idEnt: $payloadOk',
      );

      final updateResultOk = await Supabase.instance.client
          .from('entregas')
          .update(payloadOk)
          .eq('id', idEnt);

      debugPrint(
        '[DEBUG] entregas.update result (entregue) id=$idEnt: $updateResultOk',
      );

      // after successful update, notify gestor via WhatsApp
      try {
        final phone = await _getTelefoneGestor();
        final driverName = await _getDriverName();
        final mensagem =
            '📦 ENTREGA CONCLUÍDA: $clienteNome\nMotorista: $driverName\nHora: $hora';
        await enviarWhatsApp(mensagem, phone: phone);
      } catch (e) {
        debugPrint('Erro ao notificar gestor: $e');
      }

      // Após atualizar como 'entregue', buscar lista atual e tocar som de sucesso se vazia
      try {
        final prefs = await SharedPreferences.getInstance();
        final idLogado =
            prefs.getString('driver_uuid') ??
            Supabase.instance.client.auth.currentUser?.id;
        if (idLogado != null) {
          final next = await _fetchEntregasForDriver(idLogado);
          if (next.isEmpty) {
            try {
              await _tocarSomSucesso();
            } catch (e) {
              debugPrint('Erro ao tocar som de sucesso: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('Erro verificando entregas após OK: $e');
      }
    } catch (e) {
      debugPrint('[DEBUG] Erro no OK: $e');
      debugPrint('Erro ao atualizar entrega: $e');
      messenger.showSnackBar(
        SnackBar(content: Text('Erro ao finalizar entrega: ${e.toString()}')),
      );
      return;
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bom dia,';
    if (hour < 18) return 'Boa tarde,';
    return 'Boa noite,';
  }

  Future<void> _insertTestEntrega() async {
    // Developer helper: inserts a test entrega for the currently-logged driver (long-press title)
    try {
      final prefs = await SharedPreferences.getInstance();
      final motoristaId =
          prefs.getString('driver_uuid') ??
          Supabase.instance.client.auth.currentUser?.id;
      if (motoristaId == null || motoristaId.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('driver_uuid não encontrado - faça login primeiro'),
          ),
        );
        return;
      }

      final payload = {
        'cliente': 'CLIENTE TESTE V10',
        'endereco': 'Rua de Teste, 100',
        'status': 'em_rota',
        'tipo': 'Entrega',
        'motorista_id': motoristaId,
        'ordem_logistica': 999,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      debugPrint('[DEBUG] inserindo entrega de teste payload: $payload');
      final resp = await Supabase.instance.client
          .from('entregas')
          .insert(payload)
          .select();
      debugPrint('[DEBUG] insert teste entregas response: $resp');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Entrega de teste inserida: ${resp.isNotEmpty ? resp[0]['id'] : resp.toString()}',
          ),
        ),
      );
    } catch (e) {
      debugPrint('[DEBUG] erro ao inserir entrega de teste: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao inserir entrega de teste: ${e.toString()}'),
        ),
      );
    }
  }

  void _showMenuModal() async {
    final nav = Navigator.of(context);
    final nome = await _getDriverName();
    final telefoneGestor = await _getTelefoneGestor();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.deepPurpleAccent,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _greeting(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Olá, $nome!',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(color: Colors.white12),
                ListTile(
                  leading: const Icon(Icons.person, color: Colors.white),
                  title: const Text(
                    'Perfil',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.of(ctx).pop(),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.support_agent, color: Colors.white),
                  title: const Text(
                    'Falar com Gestor',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final phone = telefoneGestor;
                    if (phone.isNotEmpty) {
                      try {
                        final uri = Uri(scheme: 'tel', path: phone);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                          return;
                        }
                      } catch (_) {}
                      // fallback to WhatsApp if tel not available
                      try {
                        await enviarWhatsApp(
                          'Olá, preciso de suporte',
                          phone: phone,
                        );
                      } catch (_) {}
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Número do gestor indisponível'),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    'Sair',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    try {
                      final prefs = await SharedPreferences.getInstance();
                      final uuid = prefs.getString('driver_uuid') ?? '';
                      final id = prefs.getInt('driver_id') ?? 0;
                      final ts = DateTime.now().toUtc().toIso8601String();
                      final payload = {
                        'esta_online': false,
                        'ultima_atualizacao': ts,
                      };
                      try {
                        if (uuid.isNotEmpty) {
                          await Supabase.instance.client
                              .from('motoristas')
                              .update(payload)
                              .eq('uuid', uuid);
                        } else if (id > 0) {
                          await Supabase.instance.client
                              .from('motoristas')
                              .update(payload)
                              .eq('id', id);
                        }
                      } catch (e) {
                        debugPrint('Erro atualizando status motorista: $e');
                      }

                      try {
                        await Supabase.instance.client.auth.signOut(
                          scope: SignOutScope.local,
                        );
                      } catch (_) {
                        await Supabase.instance.client.auth.signOut();
                      }

                      try {
                        await prefs.remove('driver_uuid');
                        await prefs.remove('driver_name');
                        await prefs.remove('driver_id');
                      } catch (_) {}
                    } catch (e) {
                      debugPrint('Erro no logout: $e');
                    }

                    if (mounted) {
                      nav.pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const SplashPage()),
                        (r) => false,
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}
