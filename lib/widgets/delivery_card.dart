import 'package:flutter/material.dart';
// styles inlined for this widget to match the requested visual
import 'package:v10_delivery/core/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:v10_delivery/globals.dart';
import 'package:v10_delivery/core/utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:v10_delivery/widgets/delivery_confirmation_modal.dart';

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
    final tipoRaw = (data['tipo'] ?? '').toString().toLowerCase();
    final gestorNote = (data['gestor_obs'] ?? data['obs'] ?? '').toString();
    final Color tipoColor = tipoRaw.contains('entrega')
        ? AppColors.primary
        : tipoRaw.contains('recolha')
        ? Colors.orange
        : Colors.blueGrey;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.06 * 255).round()),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Lateral color bar
          Container(
            width: 8,
            height: 150,
            decoration: BoxDecoration(
              color: tipoColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(15),
                bottomLeft: Radius.circular(15),
              ),
            ),
          ),
          // Conteúdo
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top: circle index + tipo
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: tipoColor,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        (tipoRaw.isNotEmpty ? tipoRaw.toUpperCase() : 'OUTRO'),
                        style: TextStyle(
                          color: tipoColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // CLIENTE label + nome
                  const Text(
                    'CLIENTE',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cliente,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'ENDEREÇO',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    endereco,
                    style: TextStyle(color: Colors.grey[800], fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  // Gestor balloon
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.chat_bubble,
                          size: 16,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Gestor: ${gestorNote.isNotEmpty ? gestorNote : 'Sem avisos no DB'}',
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _openMaps(endereco),
                          icon: const Icon(Icons.map, size: 16),
                          label: const Text('ROTA'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.entrega,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            final motivo = 'FALHA';
                            if (onReportFailure != null) {
                              try {
                                await onReportFailure!(
                                  data['id']?.toString() ?? '',
                                  cliente,
                                  endereco,
                                  motivo,
                                );
                              } catch (e) {
                                debugPrint(
                                  'Erro onReportFailure: ${e.toString()}',
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.falha,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('FALHA'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            // Restore modal flow: open modal to choose recebedor
                            final result = await DeliveryConfirmationModal.show(
                              context,
                              cliente: cliente,
                              endereco: endereco,
                            );

                            if (result == null) return; // cancelled

                            final opcaoEscolhida = result['opcao'] ?? '-';
                            final nomeDigitado = (result['nome'] ?? '')
                                .toString();
                            final obs = (result['obs'] ?? '').toString();
                            final recebedorCompleto =
                                '$opcaoEscolhida: ${nomeDigitado.isNotEmpty ? nomeDigitado : '-'}';
                            debugPrint(
                              '>>> CLIQUE OK: opcao=$opcaoEscolhida nome=$nomeDigitado',
                            );

                            final id = data['id']?.toString() ?? '';
                            final nowIso = DateTime.now()
                                .toUtc()
                                .toIso8601String();
                            final payload = {
                              'status': 'entregue',
                              'recebedor': recebedorCompleto,
                              'tipo_recebedor': opcaoEscolhida,
                              'data_conclusao': nowIso,
                              'horario_conclusao': nowIso,
                            };

                            debugPrint(
                              '[DEBUG] OK Payload: id=$id payload=$payload',
                            );
                            try {
                              final res = await Supabase.instance.client
                                  .from('entregas')
                                  .update(payload)
                                  .eq('id', id);
                              debugPrint('>>> SUCESSO NO UPDATE OK <<< $res');

                              // notify gestor after success (format V10)
                              final hora = DateFormat(
                                'HH:mm',
                              ).format(DateTime.now());
                              final entregador = nomeMotorista.isNotEmpty
                                  ? nomeMotorista
                                  : 'Leandro';
                              final mensagem = StringBuffer()
                                ..writeln(
                                  '✅ *ENTREGA REALIZADA - V10 Delivery*',
                                )
                                ..writeln('🕒 *Horário:* $hora')
                                ..writeln('👤 *Cliente:* $cliente')
                                ..writeln('📍 *Endereço:* $endereco')
                                ..writeln(
                                  '🤝 *Recebido por:* $recebedorCompleto',
                                )
                                ..writeln('🚚 *Entregador:* $entregador')
                                ..writeln(
                                  '📝 *Obs:* ${obs.isNotEmpty ? obs : '-'}',
                                );
                              try {
                                await enviarWhatsApp(
                                  mensagem.toString(),
                                  phone: numeroGestor,
                                );
                              } catch (e) {
                                debugPrint('Erro ao abrir WhatsApp (OK): $e');
                              }
                            } catch (e) {
                              debugPrint('>>> ERRO NO UPDATE OK: $e <<<');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.sucesso,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('OK'),
                        ),
                      ),
                    ],
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
