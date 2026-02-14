import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class FailureConfirmationModal extends StatefulWidget {
  final Map<String, dynamic> deliveryData;
  const FailureConfirmationModal({super.key, required this.deliveryData});

  @override
  State createState() => _FailureConfirmationModalState();

  /// Returns a map with keys 'motivo' and 'obs' when the user confirms, or null when canceled.
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
          child: FailureConfirmationModal(
            deliveryData: {
              'cliente': cliente ?? '-',
              'endereco': endereco ?? '-',
            },
          ),
        );
      },
    );
  }
}

class _FailureConfirmationModalState extends State<FailureConfirmationModal> {
  String? motivoSelecionado;
  final TextEditingController obsController = TextEditingController();
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _retrieveLostData();
  }

  Future<void> _retrieveLostData() async {
    try {
      final LostDataResponse response = await _picker.retrieveLostData();
      if (response.isEmpty) return;
      if (response.file != null) {
        if (!mounted) return;
        setState(() => _imageFile = File(response.file!.path));
      }
    } catch (e) {
      debugPrint('Erro ao recuperar lost data: ${e.toString()}');
    }
  }

  final List motivos = [
    'MUDOU-SE',
    'CLIENTE NÃO ENCONTRADO',
    'VIA BLOQUEADA',
    'FALTA DE DOCUMENTO',
    'RECUSOU-SE',
    'ENDEREÇO INEXISTENTE',
    'ÁREA DE RISCO',
    'VEÍCULO QUEBRADO',
    'ESTABELECIMENTO FECHADO',
    'OUTROS',
  ];

  @override
  void dispose() {
    obsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
      );
      if (picked != null) {
        if (!mounted) return;
        setState(() => _imageFile = File(picked.path));
      }
    } catch (e) {
      debugPrint('Erro ao abrir câmera: ${e.toString()}');
    }
  }

  Future<void> _confirmAndClose() async {
    final motivo = motivoSelecionado ?? 'OUTROS';
    final obs = obsController.text.trim().isNotEmpty
        ? obsController.text.trim()
        : '-';

    if (!mounted) return;
    // Return both motivo and obs to the caller; do NOT send WhatsApp from the modal.
    Navigator.pop(context, <String, String>{'motivo': motivo, 'obs': obs});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Center(
                    child: Text(
                      "⚠️ FALHA NA ENTREGA",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _pickImage,
                  icon: Icon(
                    Icons.camera_alt,
                    color: _imageFile != null ? Colors.green : Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.5,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: motivos.length,
              itemBuilder: (context, index) {
                final motivo = motivos[index];
                final isSelected = motivoSelecionado == motivo;
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSelected ? Colors.red : Colors.grey[850],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => setState(() => motivoSelecionado = motivo),
                  child: Text(
                    motivo,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
            TextField(
              controller: obsController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[900],
                hintText: "Nome / Motivo / Observação",
                hintStyle: const TextStyle(color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            // Thumbnail (compacta) imediatamente acima do input previously; keep it with no extra spacing
            if (_imageFile != null) ...[
              SizedBox(
                height: 60,
                width: 60,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(_imageFile!, fit: BoxFit.cover),
                ),
              ),
            ],
            // Botão ENVIAR colado ao input
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: _confirmAndClose,
                child: const Text(
                  "CONFIRMAR FALHA",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
