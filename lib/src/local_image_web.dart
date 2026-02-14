import 'package:flutter/material.dart';

Widget localImageWidget(
  String path, {
  double? width,
  double? height,
  BoxFit? fit,
}) {
  // Web: não suportamos File local — mostrar ícone como fallback
  return Center(
    child: Icon(
      Icons.photo,
      size: width != null && width < 80 ? width : 48,
      color: const Color(0xFF9E9E9E),
    ),
  );
}

ImageProvider? localImageProvider(String path) {
  return null;
}
