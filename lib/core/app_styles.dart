import 'package:flutter/material.dart';
// app_colors import removed; styles reference Colors directly

class AppSpacing {
  AppSpacing._();

  static const double s8 = 8.0;
  static const double s12 = 12.0;
  static const double s16 = 16.0;
  static const double s20 = 20.0;
  static const double s30 = 30.0;
}

class AppRadius {
  AppRadius._();

  static final BorderRadius modalTop = BorderRadius.vertical(
    top: Radius.circular(20),
  );
}

class AppStyles {
  AppStyles._();

  static const TextStyle modalTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  static const TextStyle white = TextStyle(color: Colors.white);
  static const TextStyle white70 = TextStyle(color: Colors.white70);

  // Use for input field text
  static const TextStyle inputTextWhite = TextStyle(color: Colors.white);
  static const TextStyle chipLabelWhite = TextStyle(color: Colors.white);
}
