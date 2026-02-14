class ItemHistorico {
  final String nomeCliente;
  final String horario;
  final String status;
  final String? motivo;
  final String? caminhoFoto;
  final String? caminhoAssinatura;

  ItemHistorico({
    required this.nomeCliente,
    required this.horario,
    required this.status,
    this.motivo,
    this.caminhoFoto,
    this.caminhoAssinatura,
  });
}

final List<ItemHistorico> historicoEntregas = [];
