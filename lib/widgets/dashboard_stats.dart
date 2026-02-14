import 'package:flutter/material.dart';
import 'package:v10_delivery/core/app_colors.dart';
// app_styles not required here; styles are inlined for contrast

class DashboardStats extends StatelessWidget {
  final List<Map<String, dynamic>> entregas;
  final String selectedFilter;
  final void Function(String filtro)? onFilterChanged;

  const DashboardStats({
    super.key,
    required this.entregas,
    this.selectedFilter = 'TODOS',
    this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final totalEntregas = entregas
        .where(
          (e) => (e['tipo'] ?? '').toString().toLowerCase().contains('entrega'),
        )
        .length;
    final totalRecolha = entregas
        .where(
          (e) => (e['tipo'] ?? '').toString().toLowerCase().contains('recolha'),
        )
        .length;
    final totalOutros = entregas.length - totalEntregas - totalRecolha;

    Widget buildIndicador({
      required Color borderColor,
      required IconData icon,
      required String label,
      required int count,
      required String filtroKey,
    }) {
      final selected = selectedFilter.toLowerCase() == filtroKey.toLowerCase();
      return Expanded(
        child: GestureDetector(
          onTap: () => onFilterChanged?.call(filtroKey.toUpperCase()),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border.all(color: borderColor, width: selected ? 4 : 2),
              boxShadow: selected
                  ? [BoxShadow(color: borderColor.withAlpha(30), blurRadius: 6)]
                  : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: borderColor, size: 26),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.brown,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    count.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        buildIndicador(
          borderColor: AppColors.entrega,
          icon: Icons.local_shipping,
          label: 'ENTREGAS',
          count: totalEntregas,
          filtroKey: 'ENTREGA',
        ),
        const SizedBox(width: 8),
        buildIndicador(
          borderColor: AppColors.recolha,
          icon: Icons.inventory_2,
          label: 'RECOLHA',
          count: totalRecolha,
          filtroKey: 'RECOLHA',
        ),
        const SizedBox(width: 8),
        buildIndicador(
          borderColor: AppColors.outros,
          icon: Icons.more_horiz,
          label: 'OUTROS',
          count: totalOutros,
          filtroKey: 'OUTROS',
        ),
      ],
    );
  }
}
