import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color deepBlack = Color(0xFF202124);
  static const Color white = Color(0xFFFFFFFF);

  static const Color lightBackground = Color(0xFFF8F9FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceLow = Color(0xFFF1F3F4);
  static const Color lightOutline = Color(0xFF70757A);
  static const Color lightOutlineVariant = Color(0xFFDADCE0);

  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1F1F1F);
  static const Color darkSurfaceLow = Color(0xFF28292A);
  static const Color darkSurfaceHigh = Color(0xFF333436);
  static const Color darkOnSurface = Color(0xFFE8EAED);
  static const Color darkOnSurfaceVariant = Color(0xFFBDC1C6);
  static const Color darkOutline = Color(0xFF8A8D91);
  static const Color darkOutlineVariant = Color(0xFF3C4043);

  static Color highContrastForeground(Color background) {
    final luminance = background.computeLuminance();
    final blackContrast = (luminance + 0.05) / 0.05;
    final whiteContrast = 1.05 / (luminance + 0.05);
    return blackContrast >= whiteContrast ? Colors.black : Colors.white;
  }
}
