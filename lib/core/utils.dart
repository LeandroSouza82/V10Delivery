import 'package:url_launcher/url_launcher.dart';

const String numeroGestor = '5548996525008';

Future<void> enviarWhatsApp(String mensagem, {String? phone}) async {
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
