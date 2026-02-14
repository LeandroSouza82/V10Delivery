import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:v10_delivery/core/app_colors.dart';
import 'package:v10_delivery/core/utils.dart';

class ManagerNoticeModal extends StatefulWidget {
  const ManagerNoticeModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.8;
        return SizedBox(
          height: height,
          child: const ManagerNoticeModal(),
        );
      },
    );
  }

  @override
  State<ManagerNoticeModal> createState() => _ManagerNoticeModalState();
}

class _ManagerNoticeModalState extends State<ManagerNoticeModal> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _sendNotice() {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;

    // Fecha o modal primeiro para evitar State Loss
    Navigator.pop(context);

    // Envia em background após pequeno delay
    Future.delayed(const Duration(milliseconds: 100), () async {
        final String mensagem = (StringBuffer()
              ..writeln('📢 *AVISO DO MOTORISTA*')
              ..writeln('')
              ..writeln(text)
              ..writeln('')
              ..writeln('Enviado via app V10'))
            .toString();

        try {
          // share_plus abrirá apps disponíveis (WhatsApp entre eles)
          // inclui número do gestor na mensagem para referência
          // ignore: deprecated_member_use
          await Share.share('Para: $numeroGestor\n\n$mensagem');
        } catch (_) {
          // silenciar erros de plataforma
        }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Color(0xFF121212),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: const [
                  Icon(Icons.chat_bubble, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AVISAR GESTOR',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                maxLines: 5,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF0E0E0E),
                  hintText: 'Escreva seu aviso aqui...',
                  hintStyle: const TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: EdgeInsets.only(bottom: bottom > 0 ? bottom : 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                    onPressed: _sendNotice,
                    child: const Text('ENVIAR AVISO AGORA', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
