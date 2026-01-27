import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Background handler must be a top-level or static function with pragma
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  } catch (_) {}
  // Optionally handle data-only messages here.
  if (kDebugMode) {
    debugPrint('FCM BG message: ${message.messageId}');
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const MethodChannel _channel = MethodChannel('app.channel.launcher');

  Future<void> init(GlobalKey<NavigatorState>? navigatorKey) async {
    // Ensure Firebase initialized
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    } catch (_) {}

    // Register background handler
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (_) {}

    // Create native channel 'pedidos' with sound 'buzina'
    try {
      await _channel.invokeMethod('createPedidosChannel', {'sound': 'buzina'});
    } catch (_) {}

    // Request permissions (iOS/Android 13)
    try {
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    } catch (_) {}

    // Setup foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) debugPrint('FCM onMessage: ${message.messageId} ${message.notification?.title}');
      if (navigatorKey != null) {
        final ctx = navigatorKey.currentState?.overlay?.context ?? navigatorKey.currentContext;
        if (ctx != null) {
          final messenger = ScaffoldMessenger.maybeOf(ctx);
          if (messenger != null) {
            messenger.showSnackBar(SnackBar(
              content: Text(message.notification?.body ?? 'Nova notificação'),
              duration: const Duration(seconds: 4),
            ));
          }
        }
      }
    });

    // Log and persist token when available
    await logFcmToken();

    // Listen for token refreshes
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      debugPrint('FCM Token refreshed: $newToken');
      // Optionally persist or send to server here
    });
  }

  Future<void> logFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('--- NOTIFICATION SERVICE TOKEN ---');
      debugPrint(token ?? 'Token não disponível');
      debugPrint('----------------------------------');
    } catch (e) {
      debugPrint('Erro ao obter token FCM: $e');
    }
  }
}

