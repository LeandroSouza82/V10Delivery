import 'package:flutter/material.dart';
import 'package:v10_delivery/services/notification_service.dart';

class MessageCenterModal extends StatefulWidget {
  const MessageCenterModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.7;
        return SizedBox(
          height: height,
          child: const MessageCenterModal(),
        );
      },
    );
  }

  @override
  State<MessageCenterModal> createState() => _MessageCenterModalState();
}

class _MessageCenterModalState extends State<MessageCenterModal> {
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await NotificationService.fetchAvisos();
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = [];
        _loading = false;
      });
    }
  }

  void _removeMessage(int index) {
    setState(() => _messages.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF121212),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: const [
                Icon(Icons.mark_email_read, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'CENTRO DE MENSAGENS',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? const Center(child: Text('Sem mensagens', style: TextStyle(color: Colors.white)))
                      : ListView.builder(
                          itemCount: _messages.length,
                          itemBuilder: (ctx, i) {
                            final m = _messages[i];
                            final texto = (m['texto'] ?? m['conteudo'] ?? m['mensagem'] ?? m['titulo'] ?? '').toString();
                            return Card(
                              color: const Color(0xFF1A1A1A),
                              child: ListTile(
                                leading: const Icon(Icons.mail, color: Colors.white),
                                title: Text(texto, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _removeMessage(i),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
