import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:audioplayers/audioplayers.dart';
import 'package:share_plus/share_plus.dart';

// Número do gestor (formato internacional sem +). Configure aqui.
const String numeroGestor = '5548996525008';
const String prefSelectedMapKey = 'selected_map_app';

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
  WakelockPlus.enable();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(V10DeliveryApp());
}

class V10DeliveryApp extends StatelessWidget {
  const V10DeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: RotaMotorista(),
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
    with SingleTickerProviderStateMixin {
  final String nomeMotorista = "LEANDRO";
  // signature modal and related session path removed
  String? caminhoFotoSession;
  XFile? fotoEvidencia;
  late AnimationController _buscarController;
  late Animation<double> _buscarOpacity;
  bool modoDia = false;
  int _esquemaCores = 0; // 0 = padrão, 1/2/3 = esquemas
  // histórico de itens finalizados (usar historicoEntregas global)
  // Índices dos cards que estão sendo pressionados (efeito visual)
  final Set<int> _pressedIndices = {};

  // Áudio: usar única instância para evitar consumo excessivo de memória
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _searchingActive = false; // true quando animação de busca está ativa
  bool _awaitStartChama = false; // usado para iniciar loop após som final

  // DADOS GARANTIDOS PARA NÃO FICAR VAZIO
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

  // removed unused _currentCardIndex
  // Caminho da foto de falha (usado pelo modal de FALHA)
  String? imagemFalha;
  // Motivo selecionado para falha (guardado no estado para reset/inspeção)
  String? motivoFalhaSelecionada;
  // Contadores dinâmicos (iniciados com 0 por segurança de null-safety)
  int entregasFaltam = 0;
  int recolhasFaltam = 0;
  int outrosFaltam = 0;
  String? _selectedMapName;

  @override
  void initState() {
    super.initState();
    // Calcular contadores iniciais
    _atualizarContadores();
    // signature controller removed

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
        if (_searchingActive) _startChamaLoop();
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

  // TOOLS DE ÁUDIO
  // ignore: unused_element
  void _ensureAudioPlayer() {
    // agora _audioPlayer é final e inicializado na declaração, nada a fazer
  }

  // Única função de modal: `_buildSuccessModal` definida abaixo

  // antigos controles removidos

  // _finalizeDelivery removido (não referenciado)

  // removed unused helper that built WhatsApp message

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
      await _audioPlayer.play(AssetSource('audios/sucesso.mp3'));
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

  // ignore: unused_element
  Future<void> _tocarSomNovoPedido() async {
    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.stop();
      // IMPORTANTE: arquivos de áudio devem ficar em assets/audios/ e
      // serem registrados em pubspec.yaml. Evite alterar esse caminho.
      await _audioPlayer.play(AssetSource('audios/chama.mp3'));
      Future.delayed(Duration(seconds: 2), () async {
        try {
          await _audioPlayer.stop();
        } catch (_) {}
      });
    } catch (_) {}
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
  ) async {
    final hora = DateFormat('HH:mm').format(DateTime.now());
    final hasPhoto = imagemFalha != null;

    final report =
        '*Status:* Falha\n'
        '*Motivo:* $motivoFinal\n'
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
      entregas.removeWhere((c) => c['id'] == cardId);
      imagemFalha = null;
      motivoFalhaSelecionada = null;
    });

    // Se não há mais entregas, tocar som de rota concluída
    if (entregas.isEmpty) {
      setState(() => _searchingActive = false);
      try {
        await _tocarSomRotaConcluida();
      } catch (e) {
        // ignorar
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

  // Única função de modal: abre o bottom sheet de sucesso
  void _buildSuccessModal(BuildContext ctx, String nomeCliente) {
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
            final String pickedPath = pickedImageLocal?.path ?? '';
            final optionsSuccess = _opcoesEntrega
                .where((o) => o != 'PRÓPRIO')
                .toList();

            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'ENTREGA',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.left,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.camera_alt, color: Colors.white),
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
                                style: TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Nº',
                                  hintStyle: TextStyle(color: Colors.white54),
                                  filled: true,
                                  fillColor: Colors.grey[800],
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
                          fillColor: Colors.white10,
                          border: OutlineInputBorder(),
                          labelStyle: TextStyle(color: Colors.white70),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        style: TextStyle(color: Colors.white),
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
                                      if (await File(pickedPathLocal).exists())
                                        files.add(XFile(pickedPathLocal));
                                    } else {
                                      final String? fotoPath =
                                          fotoEvidencia?.path ??
                                          caminhoFotoSession;
                                      if (fotoPath != null) {
                                        if (await File(fotoPath).exists())
                                          files.add(XFile(fotoPath));
                                      }
                                    }
                                  } catch (_) {}

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
                                  } catch (_) {}

                                  final idx = entregas.indexWhere(
                                    (e) => (e['cliente'] ?? '') == nomeCliente,
                                  );
                                  if (idx != -1) {
                                    setState(() {
                                      entregas.removeAt(idx);
                                      _atualizarContadores();
                                      fotoEvidencia = null;
                                      caminhoFotoSession = null;
                                    });
                                  }

                                  if (entregas.isEmpty) {
                                    try {
                                      await _tocarSomRotaConcluida();
                                    } catch (_) {}
                                  }

                                  if (!mounted) return;
                                  Navigator.of(dialogCtx).pop();
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
      // tentar esquema nativo do Google Maps
      uriToLaunch = Uri.parse('comgooglemaps://?q=$encoded');
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
    entregasFaltam = entregas
        .where((e) => (e['tipo'] ?? '') == 'entrega')
        .length;
    recolhasFaltam = entregas
        .where((e) => (e['tipo'] ?? '') == 'recolha')
        .length;
    outrosFaltam = entregas.where((e) => (e['tipo'] ?? '') == 'outros').length;
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
        '*✅ Status:* Concluído';

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
      if (_searchingActive) setState(() => _searchingActive = false);
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
      backgroundColor: modoDia ? Colors.grey[100] : Colors.black,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(200.0),
        child: Container(
          decoration: BoxDecoration(color: Color(0xFF000D1A)),
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top,
            left: 20,
            right: 20,
            bottom: 16,
          ),
          child: Column(
            children: [
              // Linha do título e ícone de chat
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Benvindo, $nomeMotorista',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.chat_bubble, color: Colors.white),
                        onPressed: () {},
                      ),
                      Builder(
                        builder: (context) => IconButton(
                          icon: Icon(Icons.menu, color: Colors.white),
                          onPressed: () => Scaffold.of(context).openDrawer(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 20),
              // Linha com os três cards indicadores
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Card AZUL para Entregas
                  _buildIndicatorCard(
                    color: Colors.blue[900]!,
                    icon: Icons.person,
                    count: entregasFaltam,
                    label: 'ENTREGAS',
                  ),
                  // Card LARANJA para Recolhas
                  _buildIndicatorCard(
                    color: Colors.orange[900]!,
                    icon: Icons.inventory_2,
                    count: recolhasFaltam,
                    label: 'RECOLHA',
                  ),
                  // Card LILÁS para Outros
                  _buildIndicatorCard(
                    color: Colors.purple[900]!,
                    icon: Icons.more_horiz,
                    count: outrosFaltam,
                    label: 'OUTROS',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      drawer: Drawer(
        backgroundColor: modoDia ? Colors.grey[100] : Colors.black,
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(
                color: modoDia ? Colors.grey[300] : Colors.grey[900],
              ),
              accountName: Text(
                nomeMotorista,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: modoDia ? Colors.black : Colors.white,
                ),
              ),
              accountEmail: null,
              currentAccountPicture: CircleAvatar(
                backgroundColor: modoDia ? Colors.blue[200] : Colors.blue[700],
                child: Icon(
                  Icons.person,
                  color: modoDia ? Colors.blue[900] : Colors.white,
                ),
              ),
            ),
            SizedBox.shrink(),
            ListTile(
              leading: Icon(
                Icons.light_mode,
                color: modoDia ? Colors.black87 : Colors.white70,
              ),
              title: Text(
                'Modo Dia',
                style: TextStyle(color: modoDia ? Colors.black : Colors.white),
              ),
              onTap: () {
                setState(() => modoDia = !modoDia);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.color_lens,
                color: modoDia ? Colors.black87 : Colors.white70,
              ),
              title: Text(
                'Trocar Cores dos Cards (3 temas)',
                style: TextStyle(color: modoDia ? Colors.black : Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _abrirModalEsquemasCores(context);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.map_outlined,
                color: modoDia ? Colors.black87 : Colors.white70,
              ),
              title: Text(
                'Configurar GPS',
                style: TextStyle(color: modoDia ? Colors.black : Colors.white),
              ),
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
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Saindo (simulado)')));
                },
              ),
            ),
          ],
        ),
      ),
      body: Container(
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
                    SizedBox(height: 8),
                    Text(
                      'Bom trabalho, Leandro!',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
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
            : ReorderableListView.builder(
                buildDefaultDragHandles: false,
                proxyDecorator: (child, index, animation) => Material(
                  elevation: 20,
                  color: Colors.transparent,
                  child: child,
                ),
                itemCount: entregas.length,
                onReorder: (old, newIdx) {
                  setState(() {
                    if (newIdx > old) newIdx -= 1;
                    final item = entregas.removeAt(old);
                    entregas.insert(newIdx, item);
                  });
                },
                itemBuilder: (context, index) =>
                    ReorderableDelayedDragStartListener(
                      key: ValueKey(entregas[index]["id"]),
                      index: index,
                      child: _buildCard(entregas[index], index),
                    ),
              ),
      ),
    );
  }

  Widget _buildCard(Map<String, String> item, int index) {
    Color corBarra = item['tipo'] == 'recolha'
        ? Colors.orange
        : (item['tipo'] == 'outros' ? Colors.purpleAccent : Colors.blue);

    final bool pressed = _pressedIndices.contains(index);
    final double scale = pressed ? 0.98 : 1.0;

    return Container(
      key: ValueKey(item["id"]),
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _corComOpacidade(_getCorDoCard(item['tipo'] ?? ''), 0.85),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _corComOpacidade(Colors.black, 0.2),
            offset: Offset(0, 10),
            blurRadius: 20,
          ),
        ],
        border: Border.all(
          color: _corComOpacidade(Colors.white, 0.12),
          width: 0.5,
        ),
      ),
      // Ajuste do padding do card
      padding: EdgeInsets.all(20),
      child: Row(
        children: [
          // Indicador lateral arredondado
          Container(
            width: 5,
            height: 80,
            decoration: BoxDecoration(
              color: corBarra,
              borderRadius: BorderRadius.circular(10),
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
                    // Numeração dinâmica + ID
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: modoDia ? Colors.blue[700] : Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: modoDia ? Colors.white : Colors.black,
                              ),
                            ),
                          ),
                        ),
                        // removed duplicate small ID text (kept main numbered circle)
                      ],
                    ),

                    SizedBox(height: 8),

                    // TIPO (ENTREGA/RECOLHA/OUTROS)
                    Container(
                      alignment: Alignment.centerLeft,
                      height: 32,
                      child: Text(
                        item['tipo']!.toUpperCase(),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: modoDia ? Colors.black : Colors.white,
                        ),
                      ),
                    ),

                    SizedBox(height: 4),

                    // CLIENTE E ENDEREÇO
                    Text(
                      "CLIENTE: ${item['cliente']}",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFFD700),
                      ),
                    ),

                    SizedBox(height: 2),

                    Text(
                      "ENDEREÇO: ${item['endereco']}",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: modoDia ? Colors.grey[700] : Colors.grey[300],
                      ),
                    ),

                    SizedBox(height: 8),

                    // Mensagem do gestor (opaca) entre endereço e botões
                    if ((item['obs'] ?? '').isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(10),
                        margin: EdgeInsets.only(top: 6, bottom: 6),
                        decoration: BoxDecoration(
                          color: modoDia ? Colors.black12 : Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: modoDia ? Colors.black87 : Colors.white70,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item['obs'] ?? '',
                                style: TextStyle(
                                  color: Color(0xFFFFD700),
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
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: modoDia
                                  ? Colors.blue[400]!
                                  : Colors.blue[700]!,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 20,
                              ),
                              minimumSize: Size(100, 48),
                            ),
                            icon: Icon(
                              Icons.arrow_forward,
                              color: Colors.white,
                              size: 18,
                            ),
                            label: Text('MAPA'),
                            onPressed: () => _abrirMapaComPreferencia(
                              item['endereco'] ?? '',
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

                                      return AlertDialog(
                                        backgroundColor: Colors.grey[900],
                                        title: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Relatar Falha',
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                            IconButton(
                                              icon: Icon(
                                                Icons.camera_alt,
                                                color: Colors.white,
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
                                                      color: Colors.grey[850],
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
                                                            color:
                                                                Colors.white54,
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
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),

                                                SizedBox(height: 12),
                                                if (motivoSelecionadoLocal ==
                                                    'Outros Motivos') ...[
                                                  TextField(
                                                    controller:
                                                        motivoOutrosController,
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                    ),
                                                    decoration: InputDecoration(
                                                      hintText:
                                                          'Descreva o motivo',
                                                      hintStyle: TextStyle(
                                                        color: Colors.white54,
                                                      ),
                                                      filled: true,
                                                      fillColor:
                                                          Colors.grey[800],
                                                    ),
                                                  ),
                                                  SizedBox(height: 12),
                                                ],

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
                                                            final motivoFinal =
                                                                motivoSelecionadoLocal ==
                                                                        'Outros Motivos' &&
                                                                    motivoOutrosController
                                                                        .text
                                                                        .isNotEmpty
                                                                ? motivoOutrosController
                                                                      .text
                                                                : motivoSelecionadoLocal ??
                                                                      'Não informado';

                                                            final card =
                                                                entregas[index];
                                                            try {
                                                              try {
                                                                await _audioPlayer
                                                                    .setVolume(
                                                                      1.0,
                                                                    );
                                                                // IMPORTANTE: arquivos de áudio devem ficar em assets/audios/ e
                                                                // serem registrados em pubspec.yaml. Evite alterar esse caminho.
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
                                                            await _enviarFalha(
                                                              card['id'] ?? '',
                                                              card['cliente'] ??
                                                                  '',
                                                              card['endereco'] ??
                                                                  '',
                                                              motivoFinal,
                                                            );
                                                          }
                                                        : null,
                                                    child: Text(
                                                      'ENVIAR NOTIFICAÇÃO',
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
                            child: Text('FALHA'),
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
                            ),
                            onPressed: () => _buildSuccessModal(
                              context,
                              item['cliente'] ?? '',
                            ),
                            child: Text('OK'),
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

  Widget _buildIndicatorCard({
    required Color color,
    required IconData icon,
    required int count,
    required String label,
  }) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: _corComOpacidade(Colors.black, 0.3),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 30),
          SizedBox(height: 8),
          Text(
            '$count',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: _corComOpacidade(Colors.white, 0.9),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  void _abrirModalEsquemasCores(BuildContext context) {
    // Versão simplificada: alterna o esquema de cores e informa via SnackBar
    setState(() => _esquemaCores = (_esquemaCores + 1) % 4);
    final nome = _esquemaCores == 0 ? 'Padrão' : 'Esquema $_esquemaCores';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Esquema alterado: $nome')));
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

  Color _getCorDoCard(String tipo) {
    if (modoDia) {
      // VERSÕES CLARAS
      switch (_esquemaCores) {
        case 1: // Esquema 1 claro
          if (tipo == 'entrega') return Colors.red[100]!;
          if (tipo == 'recolha') return Colors.green[100]!;
          if (tipo == 'outros') return Colors.yellow[100]!;
          break;

        case 2: // Esquema 2 claro
          if (tipo == 'entrega') return Color(0xFF87CEEB);
          if (tipo == 'recolha') return Color(0xFF98FB98);
          if (tipo == 'outros') return Color(0xFFB0C4DE);
          break;

        case 3: // NOVO: Esquema 3 claro (Azul, Laranja, Lilás fraco)
          if (tipo == 'entrega') return Colors.blue[100]!;
          if (tipo == 'recolha') return Colors.orange[100]!;
          if (tipo == 'outros') return Color(0xFFF3E5F5); // Lilás muito fraco
          break;

        default: // Padrão claro
          if (tipo == 'entrega') return Colors.blue[100]!;
          if (tipo == 'recolha') return Colors.orange[100]!;
          if (tipo == 'outros') return Colors.purple[100]!;
      }
      return Colors.grey[300]!;
    } else {
      // VERSÕES ESCURAS
      switch (_esquemaCores) {
        case 1:
          if (tipo == 'entrega') return Colors.red[900]!;
          if (tipo == 'recolha') return Colors.green[900]!;
          if (tipo == 'outros') return Colors.yellow[900]!;
          break;

        case 2:
          if (tipo == 'entrega') return Color(0xFF0077be);
          if (tipo == 'recolha') return Color(0xFF8f9779);
          if (tipo == 'outros') return Color(0xFF00008b);
          break;

        case 3: // NOVO: Esquema 3 escuro (Azul, Laranja, Lilás)
          if (tipo == 'entrega') return Colors.blue[700]!;
          if (tipo == 'recolha') return Colors.orange[700]!;
          if (tipo == 'outros') return Color(0xFFD8BFD8); // Lilás fraco
          break;

        default: // Padrão escuro
          if (tipo == 'entrega') return Colors.blue[900]!;
          if (tipo == 'recolha') return Colors.orange[900]!;
          if (tipo == 'outros') return Colors.purple[900]!;
      }
      return Colors.grey[900]!;
    }
  }

  // Substitui o uso de `.withOpacity(...)` por `Color.fromRGBO(...)`
  Color _corComOpacidade(Color c, double o) {
    int alpha = (o * 255).round();
    if (alpha < 0) alpha = 0;
    if (alpha > 255) alpha = 255;
    return c.withAlpha(alpha);
  }
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
      appBar: AppBar(title: const Text('Histórico de Atividades')),
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
