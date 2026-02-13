import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:v10_delivery/core/app_styles.dart';
import 'package:v10_delivery/core/app_colors.dart';
import 'package:v10_delivery/core/constants.dart';
import 'package:v10_delivery/core/utils.dart';
import 'package:v10_delivery/services/location_service.dart';

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
  final LocationService _locationService = LocationService();
  bool _online = false;

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

  @override
  void initState() {
    super.initState();
    _atualizarContadores();

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
    final hora = DateFormat('HH:mm').format(DateTime.now());
    final hasPhoto = imagemFalha != null;

    final report =
        '❌ *RELATÓRIO DE FALHA*\n'
        'Status: Não Realizada\n'
        'Motivo: $motivoFinal\n'
        'Cliente: $cliente\n'
        'Endereço: $endereco\n'
        'Motorista: LEANDRO\n'
        'Foto: ${hasPhoto ? '✅' : '❌'}\n'
        'Hora: $hora';

    final wa = Uri.parse(
      'https://api.whatsapp.com/send?phone=$numeroGestor&text=${Uri.encodeComponent(report)}',
    );

    try {
      if (await canLaunchUrl(wa)) {
        await launchUrl(wa, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint(e.toString());
    }

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

  Future<void> _salvarMapaSelecionado(String mapName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefSelectedMapKey, mapName);
    setState(() => _selectedMapName = mapName);
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
                  title: const Text('Usar mapa web (Google Maps)'),
                  onTap: () {
                    _salvarMapaSelecionado('google_maps');
                    Navigator.of(ctx).pop();
                  },
                ),
                ...available.map((m) {
                  return ListTile(
                    leading: const Icon(Icons.map),
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
      debugPrint(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Minimal placeholder UI to keep the screen functional after migration.
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Rota Motorista'),
        actions: [
          IconButton(
            tooltip: 'Suporte (WhatsApp)',
            icon: const Icon(Icons.chat),
            onPressed: () async {
              final mensagem = 'Olá, preciso de suporte na rota.';
              try {
                await enviarWhatsApp(mensagem, phone: numeroGestor);
              } catch (e) {
                debugPrint('Erro enviarWhatsApp: ${e.toString()}');
              }
            },
          ),
          IconButton(
            tooltip: 'Preferências de mapa',
            icon: const Icon(Icons.map),
            onPressed: _abrirPreferenciasMapa,
          ),
          IconButton(
            tooltip: 'Ficar Online',
            icon: Icon(_online ? Icons.power : Icons.power_off),
            onPressed: () async {
              try {
                final prefs = await SharedPreferences.getInstance();
                final motoristaUuid =
                    prefs.getString('driver_uuid') ??
                    prefs.getInt('driver_id')?.toString() ??
                    '0';
                if (!_online) {
                  _locationService.iniciarRastreio(motoristaUuid);
                  setState(() => _online = true);
                  debugPrint('Iniciando rastreio para $motoristaUuid');
                } else {
                  _locationService.pararRastreio();
                  setState(() => _online = false);
                  debugPrint('Parando rastreio');
                }
              } catch (e) {
                debugPrint('Erro ao alternar online: ${e.toString()}');
              }
            },
          ),
        ],
      ),
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
            Expanded(
              child: entregas.isEmpty
                  ? const Center(child: Text('Nenhuma entrega pendente'))
                  : ListView.builder(
                      itemCount: entregas.length,
                      itemBuilder: (ctx, idx) {
                        final e = entregas[idx];
                        final cliente = e['cliente'] ?? '-';
                        final endereco = e['endereco'] ?? '-';
                        final id = e['id'] ?? '';
                        final tipoRaw = (e['tipo'] ?? '').toString().toLowerCase();
                        final Color borderColor = tipoRaw.contains('entrega')
                            ? AppColors.primary
                            : tipoRaw.contains('recolha')
                                ? Colors.orange
                                : Colors.purpleAccent;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          color: Colors.white,
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: borderColor, width: 3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: borderColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          id.toString(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        cliente,
                                        style: AppStyles.modalTitle.copyWith(
                                            color: AppColors.text),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  endereco,
                                  style: TextStyle(
                                    color: AppColors.text,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    ElevatedButton(
                                      onPressed: () =>
                                          _buildSuccessModal(ctx, cliente),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                      ),
                                      child: const Text('Entregue'),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: () async {
                                        final motivoCtl =
                                            TextEditingController();
                                        final confirmed = await showDialog<bool>(
                                          context: ctx,
                                          builder: (dctx) {
                                            return AlertDialog(
                                              title: const Text(
                                                'Reportar Falha',
                                              ),
                                              content: TextField(
                                                controller: motivoCtl,
                                                decoration:
                                                    const InputDecoration(
                                                  labelText: 'Motivo (opcional)',
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.of(dctx).pop(false),
                                                  child: const Text('Cancelar'),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.of(dctx).pop(true),
                                                  child: const Text('Enviar'),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                        if (confirmed == true) {
                                          final motivo =
                                              motivoCtl.text.isNotEmpty
                                                  ? motivoCtl.text
                                                  : 'Não foi possível realizar a entrega';
                                          try {
                                            await _enviarFalha(
                                              id,
                                              cliente,
                                              endereco,
                                              motivo,
                                            );
                                          } catch (e) {
                                            debugPrint(
                                              'Erro ao enviar falha: ${e.toString()}',
                                            );
                                          }
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.redAccent,
                                      ),
                                      child: const Text('Falha'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ), // ListView.builder
            ), // Expanded
          ], // Column children
        ), // Column
      ), // Padding
    ); // Scaffold
  }
}
