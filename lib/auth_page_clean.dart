import 'package:flutter/material.dart';
import 'package:v10_delivery/screens/login_screen.dart';

class AuthPageClean extends StatelessWidget {
  const AuthPageClean({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => LoginPage()),
            );
          },
          child: const Text('Ir para Login'),
        ),
      ),
    );
  }
}
