import 'package:flutter/material.dart';
import 'package:v10_delivery/core/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:v10_delivery/globals.dart';

class DeliveryConfirmationModal extends StatefulWidget {
  final String? cliente;
  final String? endereco;

  const DeliveryConfirmationModal({super.key, this.cliente, this.endereco});

  /// Helper para abrir o modal com isScrollControlled e altura ~90%
  /// Retorna um mapa com chaves 'opcao' e 'obs' quando confirmado, ou null se cancelado.
  static Future<Map<String, String>?> show(
    BuildContext context, {
    String? cliente,
    String? endereco,
  }) {
    return showModalBottomSheet<Map<String, String>?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.9;
        return SizedBox(
          height: height,
          child: DeliveryConfirmationModal(
            cliente: cliente,
            endereco: endereco,
          ),
        );
      },
    );
  }

  @override
  State<DeliveryConfirmationModal> createState() =>
      _DeliveryConfirmationModalState();
}

class _DeliveryConfirmationModalState extends State<DeliveryConfirmationModal> {
  final List<String> _options = [
    'SÍNDICO',
    'MORADOR',
    'ZELADOR',
    'PORTEIRO',
    'FAXINEIRO',
    'LOCKER',
    'CORREIO',
    'PRÓPRIO',
    'VIZINHO',
    'OUTROS',
  ];

  String? _selected;
  final TextEditingController _aptController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _obsController = TextEditingController();
  final FocusNode _obsFocus = FocusNode();

  @override
  void dispose() {
    _aptController.dispose();
    _nameController.dispose();
    _obsController.dispose();
    _obsFocus.dispose();
    super.dispose();
  }

  void _onOptionTap(String opt) {
    setState(() {
      _selected = (_selected == opt) ? null : opt;
    });

    // Se escolheu OUTROS, focar o campo de observações
    if (opt == 'OUTROS') {
      Future.delayed(const Duration(milliseconds: 120), () {
        _obsFocus.requestFocus();
      });
    }
  }

  Future<void> _onSend() async {
    final opcao = _selected ?? '-';
    final numero = _aptController.text.trim();
    final nomeRecebedor = _nameController.text.trim();
    final obs = _obsController.text.trim();

    // Return the chosen option and observation to the caller; do not perform DB or WhatsApp here.
    if (!mounted) return;
    debugPrint(
      'DeliveryConfirmationModal: opcao=$opcao numero=$numero nome=$nomeRecebedor obs=$obs at ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())} by $nomeMotorista',
    );
    Navigator.of(context).pop(<String, String>{
      'opcao': opcao,
      'numero': numero,
      'nome': nomeRecebedor,
      'obs': obs,
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 12),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.local_shipping, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'ENTREGA',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Botões grandes em 2 colunas (linhas emparelhadas)
                  Column(
                    children: [
                      // helper para criar botão grande
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _onOptionTap(_options[0]),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _selected == _options[0]
                                    ? AppColors.sucesso
                                    : const Color(0xFF2E2E2E),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(56),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _options[0],
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: _selected == _options[0]
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _onOptionTap(_options[1]),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _selected == _options[1]
                                    ? AppColors.sucesso
                                    : const Color(0xFF2E2E2E),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(56),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _options[1],
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: _selected == _options[1]
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _onOptionTap(_options[2]),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _selected == _options[2]
                                    ? AppColors.sucesso
                                    : const Color(0xFF2E2E2E),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(56),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _options[2],
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: _selected == _options[2]
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _onOptionTap(_options[3]),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _selected == _options[3]
                                    ? AppColors.sucesso
                                    : const Color(0xFF2E2E2E),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(56),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _options[3],
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: _selected == _options[3]
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _onOptionTap(_options[4]),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _selected == _options[4]
                                    ? AppColors.sucesso
                                    : const Color(0xFF2E2E2E),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(56),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _options[4],
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: _selected == _options[4]
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _onOptionTap(_options[5]),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _selected == _options[5]
                                    ? AppColors.sucesso
                                    : const Color(0xFF2E2E2E),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(56),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _options[5],
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: _selected == _options[5]
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _onOptionTap(_options[6]),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _selected == _options[6]
                                    ? AppColors.sucesso
                                    : const Color(0xFF2E2E2E),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(56),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _options[6],
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: _selected == _options[6]
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _onOptionTap(_options[7]),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _selected == _options[7]
                                    ? AppColors.sucesso
                                    : const Color(0xFF2E2E2E),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(56),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _options[7],
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: _selected == _options[7]
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _onOptionTap(_options[8]),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _selected == _options[8]
                                    ? AppColors.sucesso
                                    : const Color(0xFF2E2E2E),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(56),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _options[8],
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: _selected == _options[8]
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _onOptionTap(_options[9]),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _selected == _options[9]
                                    ? AppColors.sucesso
                                    : const Color(0xFF2E2E2E),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(56),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _options[9],
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: _selected == _options[9]
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),

                  // Nº Apartamento / Casa (condicional)
                  if (_selected != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nome do Recebedor',
                          hintText: 'Ex: Anderson',
                          filled: true,
                        ),
                      ),
                    ),
                  if (_selected == 'MORADOR')
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: TextField(
                        controller: _aptController,
                        decoration: const InputDecoration(
                          labelText: 'Nº Apartamento',
                          filled: true,
                        ),
                      ),
                    ),
                  if (_selected == 'VIZINHO')
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: TextField(
                        controller: _aptController,
                        decoration: const InputDecoration(
                          labelText: 'Nº da Casa',
                          filled: true,
                        ),
                      ),
                    ),

                  // Campo de observação destacado
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 6),
                    child: TextField(
                      focusNode: _obsFocus,
                      controller: _obsController,
                      decoration: const InputDecoration(
                        labelText: 'Nome / Motivo / Observação',
                        filled: true,
                      ),
                      maxLines: 3,
                    ),
                  ),

                  // Espaçamento para teclado e botão sempre visível
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: bottomInset > 0 ? bottomInset : 8,
                    ),
                    child: Center(
                      child: ElevatedButton(
                        onPressed: _onSend,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.sucesso,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: const Text(
                          'ENVIAR PARA GESTOR',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
