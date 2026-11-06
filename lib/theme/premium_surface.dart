import 'package:flutter/material.dart';

import 'app_design_tokens.dart';

class PremiumSurface extends StatelessWidget {
  const PremiumSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.color,
    this.borderColor,
    this.radius = AppRadius.card,
    this.elevation = AppElevation.flat,
    this.selected = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final double elevation;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final baseColor = color ?? colorScheme.surfaceContainerLow;
    final surfaceColor = selected
        ? Color.alphaBlend(
            colorScheme.primary.withValues(
              alpha: theme.brightness == Brightness.light ? 0.08 : 0.16,
            ),
            baseColor,
          )
        : baseColor;
    final resolvedBorderColor =
        borderColor ??
        (selected
            ? colorScheme.primary.withValues(
                alpha: theme.brightness == Brightness.light ? 0.38 : 0.48,
              )
            : colorScheme.outlineVariant.withValues(alpha: 0.48));

    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: resolvedBorderColor),
      ),
      child: child,
    );
  }
}
