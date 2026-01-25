import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mostra o modal de avisos.
/// Recebe funções do host para buscar avisos e atualizar o badge.
Future<void> showAvisosModal({
  required BuildContext context,
  required Future<List<Map<String, dynamic>>> Function() buscarAvisos,
  required Future<void> Function() atualizarAvisosNaoLidas,
  required int esquemaCores,
  required bool modoDia,
}) async {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: (esquemaCores == 2 || esquemaCores == 3) ? Colors.white : null,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) {
      var futureAvisos = buscarAvisos();
      return StatefulBuilder(
        builder: (modalCtx, setModalState) {
          return Container(
            height: MediaQuery.of(modalCtx).size.height * 0.6,
            padding: const EdgeInsets.all(12),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: futureAvisos,
              builder: (fCtx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final avisos = snap.data ?? [];
                if (avisos.isEmpty) {
                  return const Center(child: Text('Nenhum aviso no momento', style: TextStyle(color: Colors.black)));
                }
                return ListView.separated(
                  itemCount: avisos.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final a = avisos[i];
                    final String titulo = a['titulo']?.toString() ?? '';
                    final String mensagem = a['mensagem']?.toString() ?? '';
                    final created = a['created_at'];
                    String horario = '';
                    try {
                      final dt = DateTime.parse(created.toString()).toLocal();
                      horario = DateFormat('HH:mm').format(dt);
                    } catch (_) {
                      horario = '';
                    }
                    final lida = a['lida'];
                    final bool isLida = lida is bool ? lida : (lida?.toString().toLowerCase() == 'true');

                    return Card(
                      color: (esquemaCores == 2 || esquemaCores == 3) ? Colors.white : Colors.white,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Text(mensagem, style: const TextStyle(color: Colors.black)),
                        ),
                        leading: isLida ? null : Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (horario.isNotEmpty)
                              Flexible(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: Text(horario, style: const TextStyle(color: Colors.black54), overflow: TextOverflow.ellipsis),
                                ),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                try {
                                  // Aguarda o update no Supabase antes de alterar a UI
                                  final upd = await Supabase.instance.client
                                      .from('avisos_gestor')
                                      .update({'lida': true})
                                      .eq('id', a['id']);
                                  debugPrint('Resposta update avisos_gestor (id=${a['id']}): $upd');

                                  // Atualiza o contador de avisos não lidos no app
                                  await atualizarAvisosNaoLidas();
                                  debugPrint('Badge atualizado (após delete)');

                                  // Remover localmente do modal (síncrono dentro de setModalState)
                                  setModalState(() {
                                    avisos.removeWhere((element) => element['id'] == a['id']);
                                  });
                                } catch (e) {
                                  debugPrint('Erro ao remover aviso: $e');
                                }
                              },
                            ),
                            IconButton(
                              icon: Icon(isLida ? Icons.mark_email_read : Icons.mark_email_unread, color: Colors.black),
                              onPressed: () async {
                                try {
                                  final id = a['id'];
                                  final novo = !isLida;
                                  await Supabase.instance.client
                                      .from('avisos_gestor')
                                      .update({'lida': novo})
                                      .eq('id', id);
                                  final newFuture = buscarAvisos();
                                  setModalState(() {
                                    futureAvisos = newFuture;
                                  });
                                  await atualizarAvisosNaoLidas();
                                } catch (e) {
                                  debugPrint('Erro ao alternar leitura do aviso: $e');
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      );
    },
  ).whenComplete(() => atualizarAvisosNaoLidas());
}
