import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:v10_delivery/core/app_styles.dart';
import 'package:v10_delivery/globals.dart';
import 'package:v10_delivery/core/app_colors.dart';
import 'package:v10_delivery/core/constants.dart';
import 'package:v10_delivery/core/utils.dart';
 
import 'package:v10_delivery/widgets/dashboard_stats.dart';
import 'package:v10_delivery/widgets/delivery_card.dart';
import 'package:v10_delivery/widgets/top_header.dart';

class RotaMotorista extends StatefulWidget {
  const RotaMotorista({super.key});

  @override
  RotaMotoristaState createState() => RotaMotoristaState();
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
  String _currentFilter = 'all';

  @override
  void initState() {
    super.initState();
    _atualizarContadores();
    _loadDriverUuidFromPrefs();

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
      final mapName = prefs.getString(prefSelectedMapKey);
      if (mapName != null && mapName.isNotEmpty) {
        setState(() => _selectedMapName = mapName);
      }
    });
  }

  Future<void> _loadDriverUuidFromPrefs() async {
    try {
      if (idLogado == null) {
        final prefs = await SharedPreferences.getInstance();
        final uuid = prefs.getString('driver_uuid');
        if (uuid != null && uuid.isNotEmpty) {
          setState(() {
            idLogado = uuid;
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar driver_uuid: $e');
    }
  }

  @override
  void dispose() {
    _buscarController.dispose();
    _audioPlayer.dispose();
    _nomeController.dispose();
    _aptController.dispose();
    super.dispose();
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

  // ignore: unused_element
  void _buildSuccessModal(BuildContext ctx, String nomeCliente) {
    String? opcaoSelecionada;
    String obsTexto = '';

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.blueGrey[900],
      shape: RoundedRectangleBorder(borderRadius: AppRadius.modalTop),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.s20,
                right: AppSpacing.s20,
                top: AppSpacing.s20,
                bottom:
                    MediaQuery.of(context).viewInsets.bottom + AppSpacing.s20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'CONFIRMAR ENTREGA',
                      style: AppStyles.modalTitle,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    Text(
                      'Como foi entregue? (selecione uma opção)',
                      style: AppStyles.white70,
                    ),
                    const SizedBox(height: AppSpacing.s12),
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
                          labelStyle: AppStyles.chipLabelWhite,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Observações (opcional)',
                        filled: true,
                        fillColor: Colors.white10,
                        border: const OutlineInputBorder(),
                        labelStyle: AppStyles.white70,
                      ),
                      style: AppStyles.inputTextWhite,
                      onChanged: (v) => obsTexto = v,
                      maxLines: 3,
                    ),
                    const SizedBox(height: AppSpacing.s16),
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

  // ignore: unused_element
  Future<void> _abrirMapaComPreferencia(String endereco) async {
    final encoded = Uri.encodeComponent(endereco);
    final prefs = await SharedPreferences.getInstance();
    final sel = prefs.getString(prefSelectedMapKey) ?? '';

    Uri? uriToLaunch;

    if (sel.toLowerCase().contains('waze')) {
      uriToLaunch = Uri.parse('waze://?q=$encoded');
    } else if (sel.toLowerCase().contains('google') ||
        sel.toLowerCase().contains('maps')) {
      uriToLaunch = Uri.parse('comgooglemaps://?q=$encoded');
    } else if (sel.isNotEmpty) {
      uriToLaunch = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$encoded',
      );
    } else {
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

    try {
      await launchUrl(uriToLaunch, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint(e.toString());
      final web = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$encoded',
      );
      try {
        await launchUrl(web, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint(e.toString());
      }
    }
  }

  

  @override
  Widget build(BuildContext context) {
    debugPrint('ID Logado atual: $idLogado');
    // Minimal placeholder UI to keep the screen functional after migration.
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const TopHeader(),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Mapa selecionado: ${_selectedMapName ?? 'padrão'}",
              style: AppStyles.white70,
            ),
            const SizedBox(height: 8),

            // Stream fornece tanto os dados da lista quanto os contadores para os cards
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: Supabase.instance.client
                    .from('entregas')
                    .stream(primaryKey: ['id'])
                    .order('ordem_logistica'),
                builder: (ctx, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Erro ao carregar entregas',
                      style: AppStyles.white,
                    ),
                  );
                }

                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }

                final rows = snap.hasData
                    ? (snap.data ?? <Map<String, dynamic>>[])
                    : <Map<String, dynamic>>[];

                // Sem filtros: mostrar todas as linhas retornadas pelo stream
                final active = rows;

                final totalEntregas = active
                  .where((e) => (e['tipo'] ?? '').toString().toLowerCase().contains('entrega'))
                  .length;
                final totalRecolha = active
                  .where((e) => (e['tipo'] ?? '').toString().toLowerCase().contains('recolha'))
                  .length;
                final totalOutros = (active.length - totalEntregas - totalRecolha).clamp(0, active.length);

                // Aplicar filtro selecionado pelos cards
                final displayList = (_currentFilter == 'all')
                    ? active
                    : active.where((e) {
                        final tipo = (e['tipo'] ?? '').toString().toLowerCase();
                        if (_currentFilter == 'entrega') return tipo.contains('entrega');
                        if (_currentFilter == 'recolha') return tipo.contains('recolha');
                        if (_currentFilter == 'outros') return !tipo.contains('entrega') && !tipo.contains('recolha');
                        return true;
                      }).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DashboardStats(
                      entregasCount: totalEntregas,
                      recolhasCount: totalRecolha,
                      outrosCount: totalOutros,
                      onSelectEntregas: () => setState(() => _currentFilter = 'entrega'),
                      onSelectRecolha: () => setState(() => _currentFilter = 'recolha'),
                      onSelectOutros: () => setState(() => _currentFilter = 'outros'),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: displayList.isEmpty
                          ? const Center(
                              child: Text(
                                'Nenhuma entrega disponível',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: displayList.length,
                              itemBuilder: (ctx, idx) {
                                final item = displayList[idx];
                                final cardData = <String, String>{
                                  'id': item['id']?.toString() ?? '',
                                  'cliente': item['cliente']?.toString() ?? '',
                                  'endereco': item['endereco']?.toString() ?? '',
                                  'tipo': item['tipo']?.toString() ?? '',
                                  'obs': item['obs']?.toString() ?? '',
                                  'status': item['status']?.toString() ?? '',
                                };

                                return DeliveryCard(
                                  data: cardData,
                                  index: idx,
                                  onConfirmDelivery: _buildSuccessModal,
                                  onReportFailure: _enviarFalha,
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
          ], // Column children
        ), // Column
      ), // Padding
    ); // Scaffold
  }
}
