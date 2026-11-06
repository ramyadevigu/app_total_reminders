import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

class ThemePreferenceStore {
  const ThemePreferenceStore();

  static const String _key = 'themeMode';
  static const String _colorThemeKey = 'colorTheme';

  Future<ThemeMode> loadThemeMode() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return switch (preferences.getString(_key)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } on Exception {
      return ThemeMode.system;
    }
  }

  Future<Color> loadAccentColor() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final storedColor = preferences.getString(_colorThemeKey);
      if (storedColor == null) {
        return defaultAccentColor;
      }

      final legacyColor = _legacyAccentColors[storedColor];
      if (legacyColor != null) {
        return legacyColor;
      }

      final normalized = storedColor.startsWith('#')
          ? storedColor.substring(1)
          : storedColor;
      if (normalized.length != 6 && normalized.length != 8) {
        return defaultAccentColor;
      }
      final value = int.tryParse(normalized, radix: 16);
      if (value == null) {
        return defaultAccentColor;
      }
      return normalized.length == 8 ? Color(value) : Color(0xFF000000 | value);
    } on Exception {
      return defaultAccentColor;
    }
  }

  Future<void> saveThemeMode(ThemeMode themeMode) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(_key, themeMode.name);
    if (!saved) {
      throw StateError('Unable to save the theme preference.');
    }
  }

  Future<void> saveAccentColor(Color color) async {
    final preferences = await SharedPreferences.getInstance();
    final argb = color.toARGB32();
    final alpha = (argb >> 24) & 0xFF;
    final hex = (alpha == 255 ? argb & 0x00FFFFFF : argb)
        .toRadixString(16)
        .padLeft(alpha == 255 ? 6 : 8, '0')
        .toUpperCase();
    final saved = await preferences.setString(_colorThemeKey, '#$hex');
    if (!saved) {
      throw StateError('Unable to save the accent color preference.');
    }
  }

  static const Map<String, Color> _legacyAccentColors = {
    'blue': Color(0xFF4773FA),
    'cyan': Color(0xFF93DCED),
    'mint': Color(0xFF9CE3D3),
    'lightGreen': Color(0xFFCAE0B9),
    'peach': Color(0xFFFBD6A1),
    'pink': Color(0xFFF7BED1),
    'lavender': Color(0xFFD0C6FA),
  };
}
