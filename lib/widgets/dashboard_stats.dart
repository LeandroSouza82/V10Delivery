import 'package:flutter/material.dart';
import 'package:v10_delivery/core/app_colors.dart';

class DashboardStats extends StatelessWidget {
  final int entregasCount;
  final int recolhasCount;
  final int outrosCount;
  final VoidCallback? onSelectEntregas;
  final VoidCallback? onSelectRecolha;
  final VoidCallback? onSelectOutros;

  const DashboardStats({
    super.key,
    required this.entregasCount,
    required this.recolhasCount,
    required this.outrosCount,
    this.onSelectEntregas,
    this.onSelectRecolha,
    this.onSelectOutros,
  });

  @override
  Widget build(BuildContext context) {
    Widget buildIndicador({
      required Color borderColor,
      required IconData icon,
      required String label,
      required int count,
      VoidCallback? onTap,
    }) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border.all(color: borderColor, width: 2),
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
          count: entregasCount,
          onTap: onSelectEntregas,
        ),
        const SizedBox(width: 8),
        buildIndicador(
          borderColor: AppColors.recolha,
          icon: Icons.inventory_2,
          label: 'RECOLHA',
          count: recolhasCount,
          onTap: onSelectRecolha,
        ),
        const SizedBox(width: 8),
        buildIndicador(
          borderColor: AppColors.outros,
          icon: Icons.more_horiz,
          label: 'OUTROS',
          count: outrosCount,
          onTap: onSelectOutros,
        ),
      ],
    );
  }
}
