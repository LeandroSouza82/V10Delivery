import 'dart:io';
import 'package:flutter/widgets.dart';

Widget localImageWidget(
  String path, {
  double? width,
  double? height,
  BoxFit? fit,
}) {
  return Image.file(File(path), width: width, height: height, fit: fit);
}

ImageProvider? localImageProvider(String path) {
  return FileImage(File(path));
}
