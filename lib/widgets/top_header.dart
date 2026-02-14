import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import 'message_center_modal.dart';
import 'settings_menu_modal.dart';

class TopHeader extends StatelessWidget implements PreferredSizeWidget {
  const TopHeader({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: AppColors.background,
      elevation: 0,
      // Build a fully controlled layout so the title stays exactly centered
      flexibleSpace: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // EXTREMA ESQUERDA: ícone de mensagens
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                tooltip: 'Centro de mensagens',
                onPressed: () {
                  MessageCenterModal.show(context);
                },
              ),

              // Espaço flexível antes do título
              const Spacer(),

              // Título central exato
              const Expanded(
                flex: 0,
                child: Center(
                  child: Text(
                    'V10 Delivery',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

              // Espaço flexível depois do título
              const Spacer(),

              // EXTREMA DIREITA: menu sanduíche
              IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                tooltip: 'Menu',
                onPressed: () {
                  SettingsMenuModal.show(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
