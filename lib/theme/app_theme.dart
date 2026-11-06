import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_design_tokens.dart';

const Color defaultAccentColor = Color(0xFF4D6D9E);

ThemeData buildLightTheme([Color accentColor = defaultAccentColor]) =>
    _buildTheme(accentColor, brightness: Brightness.light);

ThemeData buildDarkTheme([Color accentColor = defaultAccentColor]) =>
    _buildTheme(accentColor, brightness: Brightness.dark);

final ThemeData lightTheme = buildLightTheme();
final ThemeData darkTheme = buildDarkTheme();

ThemeData _buildTheme(Color accentColor, {required Brightness brightness}) {
  final isLight = brightness == Brightness.light;
  final generatedColorScheme = ColorScheme.fromSeed(
    seedColor: accentColor,
    brightness: brightness,
  );
  final primary = !isLight && accentColor == defaultAccentColor
      ? generatedColorScheme.primary
      : !isLight && accentColor == Colors.black
      ? AppColors.white
      : accentColor;
  final onPrimary = AppColors.highContrastForeground(primary);
  final background = isLight
      ? AppColors.lightBackground
      : AppColors.darkBackground;
  final surface = isLight ? AppColors.lightSurface : AppColors.darkSurface;
  final surfaceLow = isLight
      ? AppColors.lightSurfaceLow
      : AppColors.darkSurfaceLow;
  final surfaceHigh = isLight
      ? AppColors.lightSurface
      : AppColors.darkSurfaceHigh;
  final outline = isLight ? AppColors.lightOutline : AppColors.darkOutline;
  final outlineVariant = isLight
      ? AppColors.lightOutlineVariant
      : AppColors.darkOutlineVariant;
  final onSurface = isLight ? AppColors.deepBlack : AppColors.darkOnSurface;
  final onSurfaceVariant = isLight
      ? const Color(0xFF596779)
      : AppColors.darkOnSurfaceVariant;
  final focusColor = isLight
      ? primary
      : Color.lerp(primary, AppColors.white, 0.18)!;
  final colorScheme = generatedColorScheme.copyWith(
    primary: primary,
    onPrimary: onPrimary,
    surface: surface,
    onSurface: onSurface,
    surfaceContainerLowest: background,
    surfaceContainerLow: surfaceLow,
    surfaceContainer: surface,
    surfaceContainerHigh: surfaceHigh,
    surfaceContainerHighest: surfaceHigh,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    outlineVariant: outlineVariant,
  );
  final textTheme =
      (isLight
              ? Typography.material2021().black
              : Typography.material2021().white)
          .apply(bodyColor: onSurface, displayColor: onSurface)
          .copyWith(
            displayLarge:
                (isLight
                        ? Typography.material2021().black.displayLarge
                        : Typography.material2021().white.displayLarge)
                    ?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -1.3,
                    ),
            displayMedium:
                (isLight
                        ? Typography.material2021().black.displayMedium
                        : Typography.material2021().white.displayMedium)
                    ?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.8,
                    ),
            headlineLarge:
                (isLight
                        ? Typography.material2021().black.headlineLarge
                        : Typography.material2021().white.headlineLarge)
                    ?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.45,
                    ),
            headlineMedium:
                (isLight
                        ? Typography.material2021().black.headlineMedium
                        : Typography.material2021().white.headlineMedium)
                    ?.copyWith(fontWeight: FontWeight.w600),
            titleLarge:
                (isLight
                        ? Typography.material2021().black.titleLarge
                        : Typography.material2021().white.titleLarge)
                    ?.copyWith(fontWeight: FontWeight.w600),
          );
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.control),
  );
  final cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.compactCard),
    side: BorderSide(color: outlineVariant.withValues(alpha: 0.48)),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    textTheme: textTheme,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    dividerTheme: DividerThemeData(
      color: outlineVariant.withValues(alpha: 0.72),
      thickness: 1,
      space: 1,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 64,
      titleTextStyle: textTheme.headlineSmall?.copyWith(
        color: onSurface,
        fontWeight: FontWeight.w500,
      ),
      actionsIconTheme: IconThemeData(color: onSurfaceVariant),
    ),
    cardTheme: CardThemeData(
      color: surfaceLow,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: cardShape,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 76,
      indicatorColor: primary.withValues(alpha: isLight ? 0.12 : 0.2),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.compactCard),
      ),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          letterSpacing: 0.1,
          color: selected ? primary : onSurfaceVariant,
        );
      }),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: controlShape,
        foregroundColor: onSurfaceVariant,
        hoverColor: primary.withValues(alpha: 0.08),
        highlightColor: primary.withValues(alpha: 0.12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: focusColor, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: colorScheme.error, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: controlShape,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: controlShape,
        side: BorderSide(color: outlineVariant),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: controlShape,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceLow,
      selectedColor: primary.withValues(alpha: isLight ? 0.12 : 0.2),
      side: BorderSide(color: outlineVariant.withValues(alpha: 0.72)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      labelStyle: TextStyle(color: onSurface),
      secondaryLabelStyle: TextStyle(color: onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 10,
      iconColor: onSurfaceVariant,
      textColor: onSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaceHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.modal),
        side: BorderSide(color: outlineVariant.withValues(alpha: 0.5)),
      ),
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: onSurface,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: onSurfaceVariant),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surfaceHigh,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: outline,
      dragHandleSize: const Size(40, 4),
      elevation: 4,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.modal),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.compactCard),
        side: BorderSide(color: outlineVariant.withValues(alpha: 0.72)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected) ? onPrimary : null;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? primary
            : colorScheme.surfaceContainerHigh;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected) ? primary : outlineVariant;
      }),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: colorScheme.surfaceContainerHigh,
      circularTrackColor: colorScheme.surfaceContainerHigh,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isLight
          ? const Color(0xFF202B3A)
          : AppColors.darkSurfaceHigh,
      contentTextStyle: const TextStyle(color: AppColors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.compactCard),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: primary,
      selectionColor: primary.withValues(alpha: 0.24),
      selectionHandleColor: primary,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: onPrimary,
      elevation: 2,
      focusElevation: 3,
      hoverElevation: 3,
      highlightElevation: 1,
      shape: const CircleBorder(),
    ),
  );
}
