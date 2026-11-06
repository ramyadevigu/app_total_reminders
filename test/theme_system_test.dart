import 'package:app_smarana/app/app.dart';
import 'package:app_smarana/theme/app_colors.dart';
import 'package:app_smarana/theme/app_design_tokens.dart';
import 'package:app_smarana/theme/app_theme.dart';
import 'package:app_smarana/theme/theme_preference_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Android uses Material page transitions', () {
    expect(
      buildLightTheme().pageTransitionsTheme.builders[TargetPlatform.android],
      isA<ZoomPageTransitionsBuilder>(),
    );
  });

  test('floating add actions use a circular shape in both themes', () {
    expect(
      buildLightTheme().floatingActionButtonTheme.shape,
      isA<CircleBorder>(),
    );
    expect(
      buildDarkTheme().floatingActionButtonTheme.shape,
      isA<CircleBorder>(),
    );
  });

  test('default theme uses a tonal blue primary in both brightness modes', () {
    final lightTheme = buildLightTheme();
    final darkTheme = buildDarkTheme();

    expect(lightTheme.colorScheme.primary, isNot(Colors.black));
    expect(darkTheme.colorScheme.primary, isNot(Colors.black));
    expect(
      lightTheme.colorScheme.primary,
      isNot(darkTheme.colorScheme.primary),
    );
    expect(
      AppColors.highContrastForeground(lightTheme.colorScheme.primary),
      lightTheme.colorScheme.onPrimary,
    );
    expect(
      AppColors.highContrastForeground(darkTheme.colorScheme.primary),
      darkTheme.colorScheme.onPrimary,
    );
  });

  testWidgets('component motion respects reduced-motion preferences', (
    tester,
  ) async {
    late Duration resolvedDuration;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              resolvedDuration = AppMotion.resolve(context, AppMotion.screen);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(resolvedDuration, Duration.zero);
  });

  testWidgets('theme selection switches immediately and persists', (
    tester,
  ) async {
    await tester.pumpWidget(const AppSmarana());
    await _openSettings(tester);

    expect(_themeMode(tester), ThemeMode.system);
    expect(
      _activeBrightness(tester),
      tester.binding.platformDispatcher.platformBrightness,
    );

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(_themeMode(tester), ThemeMode.light);
    expect(_activeBrightness(tester), Brightness.light);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(_themeMode(tester), ThemeMode.dark);
    expect(_activeBrightness(tester), Brightness.dark);

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(_themeMode(tester), ThemeMode.system);
    expect(
      (await SharedPreferences.getInstance()).getString('themeMode'),
      'system',
    );
  });

  testWidgets('system mode follows operating system brightness', (
    tester,
  ) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    await tester.pumpWidget(const AppSmarana());
    await _openSettings(tester);
    expect(_activeBrightness(tester), Brightness.light);

    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    await tester.pumpAndSettle();
    expect(_themeMode(tester), ThemeMode.system);
    expect(_activeBrightness(tester), Brightness.dark);
  });

  testWidgets('saved theme mode is restored after app recreation', (
    tester,
  ) async {
    await tester.pumpWidget(const AppSmarana());
    await _openSettings(tester);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    final restoredThemeMode = await const ThemePreferenceStore()
        .loadThemeMode();
    await tester.pumpWidget(AppSmarana(initialThemeMode: restoredThemeMode));

    expect(_themeMode(tester), ThemeMode.dark);
    expect(_activeBrightness(tester), Brightness.dark);
  });

  testWidgets('custom accent color updates and persists', (tester) async {
    await tester.pumpWidget(const AppSmarana());
    await _openSettings(tester);

    final picker = find.byKey(const ValueKey('settings-accent-color-picker'));
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(find.text('Choose accent color'), findsOneWidget);
    expect(find.byKey(const ValueKey('accent-color-wheel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('accent-lightness-slider')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('accent-preset-1')));
    await tester.pumpAndSettle();
    var appTheme = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(appTheme.theme!.colorScheme.primary, const Color(0xFF008CFF));

    final hexInput = find.byKey(const ValueKey('accent-hex-input'));
    await tester.enterText(hexInput, '#12GGFF');
    await tester.pumpAndSettle();
    expect(find.text('Enter 6 or 8 hexadecimal digits.'), findsOneWidget);
    appTheme = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(appTheme.theme!.colorScheme.primary, const Color(0xFF008CFF));

    final wheel = find.byKey(const ValueKey('accent-color-wheel'));
    await tester.drag(wheel, const Offset(0, -72));
    await tester.pumpAndSettle();
    appTheme = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(appTheme.theme!.colorScheme.primary, isNot(const Color(0xFF008CFF)));

    await tester.enterText(hexInput, '#00A896');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    appTheme = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final selectedAccent = appTheme.theme!.colorScheme.primary;
    expect(selectedAccent, const Color(0xFF00A896));
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('colorTheme'), '#00A896');

    await tester.pumpWidget(const SizedBox.shrink());
    final restoredAccent = await const ThemePreferenceStore().loadAccentColor();
    expect(restoredAccent, selectedAccent);
    await tester.pumpWidget(AppSmarana(initialAccentColor: restoredAccent));
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .theme!
          .colorScheme
          .primary,
      selectedAccent,
    );
  });

  testWidgets('curated color themes update and persist', (tester) async {
    await tester.pumpWidget(const AppSmarana());
    await _openSettings(tester);

    final picker = find.byKey(const ValueKey('settings-color-theme-picker'));
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Color theme'),
      ),
      findsOneWidget,
    );
    final green = find.byKey(const ValueKey('color-theme-green'));
    expect(green, findsOneWidget);
    await tester.ensureVisible(green);
    await tester.pumpAndSettle();
    await tester.tap(green);
    await tester.pumpAndSettle();

    final expected = const Color(0xFF188038);
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .theme!
          .colorScheme
          .primary,
      expected,
    );
    expect(
      (await SharedPreferences.getInstance()).getString('colorTheme'),
      '#188038',
    );
  });

  test('custom accent colors have readable primary foregrounds', () {
    for (var hue = 0; hue <= 360; hue += 15) {
      final accentColor = HSLColor.fromAHSL(
        1,
        hue.toDouble(),
        0.8,
        0.5,
      ).toColor();
      for (final theme in [
        buildLightTheme(accentColor),
        buildDarkTheme(accentColor),
      ]) {
        final primary = theme.colorScheme.primary;
        final foreground = theme.colorScheme.onPrimary;
        final luminance = primary.computeLuminance();
        final foregroundLuminance = foreground.computeLuminance();
        final lighter = luminance > foregroundLuminance
            ? luminance
            : foregroundLuminance;
        final darker = luminance > foregroundLuminance
            ? foregroundLuminance
            : luminance;

        expect(
          (lighter + 0.05) / (darker + 0.05),
          greaterThanOrEqualTo(4.5),
          reason: '$accentColor ${theme.brightness} primary contrast',
        );
      }
    }
  });

  test('previously selected named colors remain supported', () async {
    SharedPreferences.setMockInitialValues({'colorTheme': 'lavender'});

    expect(
      await const ThemePreferenceStore().loadAccentColor(),
      const Color(0xFFD0C6FA),
    );
  });

  test(
    '8-digit accent colors preserve their alpha when saved and restored',
    () async {
      SharedPreferences.setMockInitialValues({});
      const accent = Color(0x80008CFF);
      const store = ThemePreferenceStore();

      await store.saveAccentColor(accent);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('colorTheme'), '#80008CFF');
      expect(await store.loadAccentColor(), accent);
    },
  );

  testWidgets('accent color picker works on a compact screen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const AppSmarana());
    await _openSettings(tester);
    final picker = find.byKey(const ValueKey('settings-accent-color-picker'));
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();

    expect(find.text('Choose accent color'), findsOneWidget);
    expect(find.byKey(const ValueKey('accent-color-wheel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('accent-lightness-slider')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reminders, form, and pickers use light and dark themes', (
    tester,
  ) async {
    await tester.pumpWidget(const AppSmarana());

    for (final (modeLabel, brightness) in [
      ('Light', Brightness.light),
      ('Dark', Brightness.dark),
    ]) {
      await _openSettings(tester);
      await tester.tap(find.text(modeLabel));
      await tester.pumpAndSettle();

      await tester.pageBack();
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.byKey(const ValueKey('nav-alarms')));
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(_activeBrightness(tester), brightness);

      await tester.tap(find.byType(FloatingActionButton).hitTestable());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('title-field')), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byKey(const ValueKey('title-field'))))
            .brightness,
        brightness,
      );

      await tester.tap(find.byKey(const ValueKey('date-field')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(DatePickerDialog))).brightness,
        brightness,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('time-field')));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(TimePickerDialog))).brightness,
        brightness,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
  });
}

Future<void> _openSettings(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.tap(find.byKey(const ValueKey('app-overflow-menu')).hitTestable());
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.tap(find.text('Settings'));
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.text('Appearance'), findsOneWidget);
}

ThemeMode _themeMode(WidgetTester tester) {
  return tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode ??
      ThemeMode.system;
}

Brightness _activeBrightness(WidgetTester tester) {
  return Theme.of(tester.element(find.byType(Scaffold).first)).brightness;
}
