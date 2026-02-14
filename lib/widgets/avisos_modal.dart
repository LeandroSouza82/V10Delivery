import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:v10_delivery/services/supabase_service.dart';

typedef BuscarAvisos = Future<List<Map<String, dynamic>>> Function();
typedef AtualizarAvisos = Future<void> Function();

/// Exibe o modal de avisos do gestor. Mantém a lógica idêntica ao código
/// original que estava embutido em `main.dart`.
void showAvisosModal({
  required BuildContext context,
  required BuscarAvisos buscarAvisos,
  required AtualizarAvisos atualizarAvisosNaoLidas,
  required int esquemaCores,
  required bool modoDia,
}) {
  final modalFuture = showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: (esquemaCores == 2 || esquemaCores == 3)
        ? Colors.white
        : null,
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
                  return const Center(
                    child: Text(
                      'Nenhum aviso no momento',
                      style: TextStyle(color: Colors.black),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: avisos.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
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
                    final bool isLida = lida is bool
                        ? lida
                        : (lida?.toString().toLowerCase() == 'true');
                    return Card(
                      color: (esquemaCores == 2 || esquemaCores == 3)
                          ? Colors.white
                          : Colors.white,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        title: Text(
                          titulo,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Text(
                            mensagem,
                            style: const TextStyle(color: Colors.black),
                          ),
                        ),
                        leading: isLida
                            ? null
                            : Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                        trailing: SizedBox(
                          width: 84,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (horario.isNotEmpty)
                                Text(
                                  horario,
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              IconButton(
                                icon: Icon(
                                  isLida
                                      ? Icons.mark_email_read
                                      : Icons.mark_email_unread,
                                  color: Colors.black,
                                ),
                                onPressed: () async {
                                  try {
                                    final id = a['id'];
                                    final novo = !isLida;
                                    await SupabaseService.toggleAvisoLido(
                                      id,
                                      novo,
                                    );
                                    setModalState(
                                      () => futureAvisos = buscarAvisos(),
                                    );
                                    await atualizarAvisosNaoLidas();
                                  } catch (e) {
                                    debugPrint(
                                      'Erro ao alternar leitura do aviso: $e',
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
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
  );

  modalFuture.whenComplete(() => atualizarAvisosNaoLidas());
}
