import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart'; // importante: usa a App principal definida em main.dart

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _iniciarApp();
  }

  Future<void> _iniciarApp() async {
    await Future.delayed(const Duration(seconds: 5));

    final prefs = await SharedPreferences.getInstance();
    final bool logado = prefs.getBool('logado') ?? false;

    if (!mounted) return;

    if (logado) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const V10DeliveryApp()),
      );
    } else {
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

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _manterLogado = false;
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _telController = TextEditingController();

  @override
  void dispose() {
    _nomeController.dispose();
    _telController.dispose();
    super.dispose();
  }

  Future<void> _onEntrar() async {
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
    // Só marca 'logado' como true se o checkbox estiver marcado
    if (_manterLogado) {
      await prefs.setBool('logado', true);
    } else {
      await prefs.setBool('logado', false);
    }
    await prefs.setString('motorista_nome', nome);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const V10DeliveryApp()),
    );
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

                    // Checkbox alinhado à esquerda
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
                      onPressed: _onEntrar,
                      child: const Text(
                        'ENTRAR',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Botão Sair no canto inferior esquerdo
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 12),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                  ),
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
