import 'package:flutter/material.dart';
import 'main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

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
    // Após splash, sempre enviar para a tela de login (ajuste solicitado)
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      body: Center(
        child: Image.asset('assets/images/preto.png', width: 220),
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

  @override
  void dispose() {
    _nomeController.dispose();
    _telController.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    final nome = _nomeController.text.trim();
    final tel = _telController.text.trim();
    if (nome.isEmpty || tel.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, preencha todos os campos')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (_manterLogado) {
      await prefs.setBool('logado', true);
    }
    await prefs.setString('motorista_nome', nome);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const V10DeliveryApp()),
    );
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
                          onChanged: (v) => setState(() => _manterLogado = v ?? false),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _entrar,
                      child: const Text(
                        'ENTRAR',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
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
                  onPressed: _sair,
                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                  child: const Text('Sair'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
