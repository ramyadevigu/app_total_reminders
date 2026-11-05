import 'package:flutter/material.dart';

class AppColorTheme {
  const AppColorTheme({required this.name, required this.primary});

  final String name;
  final Color primary;
}

const List<AppColorTheme> appColorThemes = [
  AppColorTheme(name: 'Calm Blue', primary: Color(0xFF4D6D9E)),
  AppColorTheme(name: 'Black & White', primary: Color(0xFF000000)),
  AppColorTheme(name: 'Blue', primary: Color(0xFF1A73E8)),
  AppColorTheme(name: 'Teal', primary: Color(0xFF008577)),
  AppColorTheme(name: 'Green', primary: Color(0xFF188038)),
  AppColorTheme(name: 'Coral', primary: Color(0xFFD95F45)),
  AppColorTheme(name: 'Amber', primary: Color(0xFFB77900)),
  AppColorTheme(name: 'Rose', primary: Color(0xFFC5225D)),
  AppColorTheme(name: 'Violet', primary: Color(0xFF7654C8)),
  AppColorTheme(name: 'Graphite', primary: Color(0xFF5F6368)),
];
