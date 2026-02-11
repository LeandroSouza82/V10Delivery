import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';

Widget localImageWidget(
  String path, {
  double? width,
  double? height,
  BoxFit? fit,
}) {
  // Web / fallback: mostrar ícone genérico quando não há suporte a File
  return Center(
    child: Icon(
      Icons.photo,
      size: width != null && width < 80 ? width : 48,
      color: const Color(0xFF9E9E9E),
    ),
  );
}

ImageProvider? localImageProvider(String path) {
  // Sem suporte a arquivo local aqui; retornar nulo para usar fallback
  return null;
}
