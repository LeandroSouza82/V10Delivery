import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';

// Background handler must be a top-level or static function with pragma
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  } catch (_) {}
  if (kDebugMode) {
    debugPrint('FCM BG message: ${message.messageId}');
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const MethodChannel _channel = MethodChannel('app.channel.launcher');

  /// Inicializa Firebase Messaging, registra handlers, cria canal 'pedidos'
  Future<void> initialize(GlobalKey<NavigatorState>? navigatorKey) async {
    // Ensure Firebase initialized
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    } catch (_) {}

    // Register background handler
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (_) {}

    // Create native channel 'pedidos' with sound 'buzina' (no extension)
    try {
      await _channel.invokeMethod('createPedidosChannel', {'sound': 'buzina'});
    } catch (_) {}

    // Request notification permissions
    AuthorizationStatus? permissionStatus;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      permissionStatus = settings.authorizationStatus;
      debugPrint('Notification permission status: $permissionStatus');
    } catch (e) {
      debugPrint('Erro ao solicitar permissão de notificações: $e');
    }

    // Foreground messages: just log for now
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) debugPrint('FCM onMessage: ${message.messageId} ${message.notification?.title}');
    });

    // If notifications were granted, and user is authenticated, ask for overlay permission (with dialog)
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if ((permissionStatus == AuthorizationStatus.authorized || permissionStatus == AuthorizationStatus.provisional) && user != null && navigatorKey != null) {
        // Show explanatory dialog before opening overlay settings
        final ctx = navigatorKey.currentState?.overlay?.context ?? navigatorKey.currentContext;
        if (ctx != null) {
          final open = await showDialog<bool>(
            context: ctx,
            builder: (ctx2) => AlertDialog(
              title: const Text('Permissão de Sobreposição'),
              content: const Text('Para que o ícone flutuante funcione, o app precisa de permissão de sobreposição. Deseja abrir as configurações agora?'),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx2).pop(false), child: const Text('Depois')),
                TextButton(onPressed: () => Navigator.of(ctx2).pop(true), child: const Text('Abrir Configurações')),
              ],
            ),
          );
          if (open == true) {
            try {
              await _channel.invokeMethod('openOverlaySettings');
            } catch (_) {}
          }
        }
      }

      // After sequence, obtain token and save if possible
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await printFcmToken();
        await saveTokenToSupabase(token);
      }
    } catch (e) {
      debugPrint('Erro na sequência de permissões/inicialização: $e');
    }

    // Listen for token refreshes and save to Supabase
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      debugPrint('FCM Token refreshed: $newToken');
      if (newToken != null && newToken.isNotEmpty) {
        await saveTokenToSupabase(newToken);
      }
    });
  }

  /// Obtém e mostra o token FCM no log
  Future<void> printFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('--- FCM TOKEN (NotificationService) ---');
      debugPrint(token ?? 'Token não disponível');
      debugPrint('---------------------------------------');
    } catch (e) {
      debugPrint('Erro ao obter token FCM: $e');
    }
  }

  /// Salva o token no Supabase na tabela `profiles` (direto ao ponto)
  Future<void> saveTokenToSupabase(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      print('⚠️ Nenhum usuário logado para salvar o token.');
      return;
    }

    final userId = user.id; // usar auth.uid() explicitamente
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', userId);
      print('✅ Token salvo com sucesso na tabela profiles (id: $userId)!');
    } catch (e) {
      print('❌ Erro ao salvar na tabela profiles (id: $userId): $e');
    }
  }
}

