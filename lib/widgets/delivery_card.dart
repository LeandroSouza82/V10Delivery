import 'package:flutter/material.dart';
// app_styles not required here; styles are inlined for compact card
// styles: using material colors directly here to match design
import 'package:url_launcher/url_launcher.dart';
import 'package:v10_delivery/widgets/delivery_confirmation_modal.dart';
import 'package:v10_delivery/widgets/failure_confirmation_modal.dart';

typedef ConfirmDeliveryCallback =
    void Function(BuildContext context, String nomeCliente);
typedef ReportFailureCallback =
    Future<void> Function(
      String id,
      String cliente,
      String endereco,
      String motivo,
    );

class DeliveryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final int index;
  final ConfirmDeliveryCallback? onConfirmDelivery;
  final ReportFailureCallback? onReportFailure;

  const DeliveryCard({
    super.key,
    required this.data,
    required this.index,
    this.onConfirmDelivery,
    this.onReportFailure,
  });

  Future<void> _openMaps(String endereco) async {
    final encoded = Uri.encodeComponent(endereco);
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$encoded',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Erro ao abrir mapa: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cliente = (data['cliente'] ?? '-') as String;
    final endereco = (data['endereco'] ?? '-') as String;
    final id = (data['id'] ?? '') as String;
    // tipo not used visually in this layout
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      color: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Indicador lateral roxo
          Container(
            width: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.deepPurple,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cabeçalho: círculo com número + tipo
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.deepPurple,
                        child: Text(
                          id.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        (data['tipo'] ?? 'OUTROS').toString().toUpperCase(),
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // CLIENTE label + nome
                  const Text('CLIENTE', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    cliente,
                    style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),

                  // ENDEREÇO label + endereco
                  const Text('ENDEREÇO', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    endereco,
                    style: const TextStyle(color: Colors.black87, fontSize: 16),
                  ),
                  const SizedBox(height: 10),

                  // Balão de aviso do gestor / obs (azul claro específico)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline, size: 16, color: Colors.black54),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            (data['obs'] ?? 'Gestor: Sem avisos no DB').toString(),
                            style: const TextStyle(color: Colors.black87, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Botões de ação (altura fixa para evitar overflow)
                  SizedBox(
                    height: 50,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _openMaps(endereco),
                            icon: const Icon(Icons.map, size: 16),
                            label: const Text('ROTA'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final motivo = await FailureConfirmationModal.show(
                                context,
                                cliente: cliente,
                                endereco: endereco,
                              );
                              if (motivo != null) {
                                if (onReportFailure != null) {
                                  try {
                                    await onReportFailure!(id, cliente, endereco, motivo);
                                  } catch (e) {
                                    debugPrint('Erro onReportFailure: ${e.toString()}');
                                  }
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('FALHA'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 52,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: () async {
                              final res = await showModalBottomSheet<dynamic>(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.blueGrey[900],
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                                ),
                                builder: (ctx) => DeliveryConfirmationModal(
                                  id: id,
                                  cliente: cliente,
                                  endereco: endereco,
                                ),
                              );
                              if (res != null && res is Map<String, dynamic>) {
                                // ignore: use_build_context_synchronously
                                onConfirmDelivery?.call(context, cliente);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              shape: const CircleBorder(),
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(0),
                            ),
                            child: const Icon(Icons.check, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
