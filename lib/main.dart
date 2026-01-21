import 'package:flutter/material.dart';

void main() => runApp(V10DeliveryApp());

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

class RotaMotorista extends StatefulWidget {
  const RotaMotorista({super.key});

  @override
  RotaMotoristaState createState() => RotaMotoristaState();
}

class RotaMotoristaState extends State<RotaMotorista> {
  final String nomeMotorista = "LEANDRO";
  bool modoDia = false;
  int _esquemaCores = 0; // 0 = padrão, 1/2/3 = esquemas
  // Índices dos cards que estão sendo pressionados (efeito visual)
  final Set<int> _pressedIndices = {};

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
  // Contadores dinâmicos (iniciados com 0 por segurança de null-safety)
  int entregasFaltam = 0;
  int recolhasFaltam = 0;
  int outrosFaltam = 0;

  @override
  void initState() {
    super.initState();
    // Calcular contadores iniciais
    _atualizarContadores();
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

  void _removerItem(int index) {
    if (index >= 0 && index < entregas.length) {
      setState(() {
        entregas.removeAt(index);
        _atualizarContadores();
      });
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
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(nomeMotorista),
              accountEmail: null,
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, color: Colors.black),
              ),
            ),
            ListTile(
              leading: Icon(Icons.history),
              title: Text('Histórico'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Abrindo Histórico (simulado)')),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.light_mode),
              title: Text('Modo Dia'),
              onTap: () {
                setState(() => modoDia = !modoDia);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.color_lens),
              title: Text('Trocar Cores dos Cards (2 temas)'),
              onTap: () {
                Navigator.pop(context);
                _abrirModalEsquemasCores(context);
              },
            ),
            Spacer(),
            ListTile(
              leading: Icon(Icons.exit_to_app, color: Colors.red),
              title: Text('Sair', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Saindo (simulado)')));
              },
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
        child: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          proxyDecorator: (child, index, animation) =>
              Material(elevation: 20, color: Colors.transparent, child: child),
          itemCount: entregas.length,
          onReorder: (old, newIdx) {
            setState(() {
              if (newIdx > old) newIdx -= 1;
              final item = entregas.removeAt(old);
              entregas.insert(newIdx, item);
            });
          },
          itemBuilder: (context, index) => ReorderableDelayedDragStartListener(
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
        border: Border.all(color: _corComOpacidade(Colors.white, 0.12), width: 0.5),
      ),
      // AUMENTADO O PADDING INTERNO
      padding: EdgeInsets.all(24),
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
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          item["id"]!,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            letterSpacing: 0.5,
                            fontSize: 30,
                            fontWeight: FontWeight.w600,
                            color: modoDia ? Colors.black87 : Colors.white,
                          ),
                        ),
                        Text(
                          item['tipo']!.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            color: corBarra,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      "CLIENTE: ${item['cliente']}",
                      style: TextStyle(
                        fontFamily: 'Inter',
                        letterSpacing: 0.5,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: modoDia ? Colors.black87 : Colors.white,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      "ENDEREÇO: ${item['endereco']}",
                      style: TextStyle(
                        fontSize: 14,
                        color: modoDia
                          ? _corComOpacidade(Colors.black87, 0.6)
                          : _corComOpacidade(Colors.white, 0.6),
                      ),
                    ),
                    SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12),
                      color: Colors.black26,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'OBS GESTOR: ',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            TextSpan(text: item['obs'] ?? ''),
                          ],
                        ),
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ),
                    SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _btn(
                          modoDia ? Colors.blue[300]! : Colors.blue[700]!,
                          "MAPA",
                        ),
                        _btn(
                          modoDia ? Colors.red[300]! : Colors.red[700]!,
                          "FALHA",
                          action: () => _removerItem(index),
                        ),
                        _btn(
                          modoDia ? Colors.green[400]! : Colors.green[700]!,
                          "OK",
                          action: () => _removerItem(index),
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

  Widget _btn(Color c, String t, {VoidCallback? action}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: c,
        foregroundColor: modoDia ? Colors.black : Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: TextStyle(fontSize: 14),
      ),
      onPressed: action ?? () {},
      child: Text(
        t,
        style: TextStyle(
          color: modoDia ? Colors.black : Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.45,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(25),
            topRight: Radius.circular(25),
          ),
        ),
        padding: EdgeInsets.only(top: 20, left: 20, right: 20, bottom: 25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CABEÇALHO COM TÍTULO
            Center(
              child: Column(
                children: [
                  Text(
                    'Escolha um esquema de cores',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Todas as cores dos cards serão alteradas juntas',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            ),

            SizedBox(height: 25),

            // OPÇÃO 1
            _buildOpcaoEsquema(
              context: context,
              titulo: 'Esquema 1',
              subtitulo: 'Vermelho - Verde - Amarelo',
              cores: [
                Colors.red[900]!,
                Colors.green[900]!,
                Colors.yellow[900]!,
              ],
              indice: 1,
            ),

            SizedBox(height: 16),

            // OPÇÃO 2
            _buildOpcaoEsquema(
              context: context,
              titulo: 'Esquema 2',
              subtitulo: 'Azul Oceano - Verde Musgo - Azul Escuro',
              cores: [Color(0xFF0077be), Color(0xFF8f9779), Color(0xFF00008b)],
              indice: 2,
            ),

            // BOTÃO DE CANCELAR OU VOLTAR
            Spacer(),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancelar',
                  style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
      // versões claras para modo dia
      switch (_esquemaCores) {
        case 1:
          if (tipo == 'entrega') return Colors.red[100]!;
          if (tipo == 'recolha') return Colors.green[100]!;
          if (tipo == 'outros') return Colors.yellow[100]!;
          break;
        case 2:
          if (tipo == 'entrega') return Color(0xFF87CEEB); // céu claro
          if (tipo == 'recolha') return Color(0xFF98FB98); // verde menta claro
          if (tipo == 'outros') return Color(0xFFB0C4DE); // azul aço claro
          break;
        default:
          if (tipo == 'entrega') return Colors.blue[100]!;
          if (tipo == 'recolha') return Colors.orange[100]!;
          if (tipo == 'outros') return Colors.purple[100]!;
      }
      return Colors.grey[300]!;
    } else {
      // versões escuras existentes
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
        default:
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
