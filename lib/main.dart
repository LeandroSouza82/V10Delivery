import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/supabase_service.dart';
import 'core/app_colors.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Trava a orientação em modo retrato apenas
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await dotenv.load(fileName: '.env');
    await SupabaseService.initializeFromEnv();
  } catch (e) {
    debugPrint('ERRO CRITICO NA INICIALIZACAO: $e');
  }

  runApp(const V10DeliveryApp());
}

class V10DeliveryApp extends StatelessWidget {
  const V10DeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'V10 Delivery',
      theme: ThemeData(
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        useMaterial3: true,
      ),
      initialRoute: '/login',
      routes: {
        '/': (context) => const _PlaceholderScreen(),
        '/login': (context) => const LoginPage(),
        '/rota': (context) => const RotaMotorista(),
      },
    );
  }
}

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('V10 Delivery')),
      body: const Center(
        child: Text('Tela inicial — pronta para modularização'),
      ),
    );
  }
}
