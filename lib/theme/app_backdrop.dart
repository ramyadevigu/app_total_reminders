import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return ColoredBox(
      color: isLight ? AppColors.lightBackground : AppColors.darkBackground,
      child: child,
    );
  }
}
