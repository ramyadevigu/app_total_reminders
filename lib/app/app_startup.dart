import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_preference_store.dart';
import 'app.dart';

class AppStartup extends StatefulWidget {
  const AppStartup({super.key});

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  late Future<_AppStartupConfiguration> _startup;

  @override
  void initState() {
    super.initState();
    _startup = _initializeApplication();
  }

  Future<void> _retryInitialization() async {
    setState(() {
      _startup = _initializeApplication();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AppStartupConfiguration>(
      future: _startup,
      builder: (context, snapshot) {
        final configuration = snapshot.data;
        if (configuration != null) {
          return AppSmarana(
            initialThemeMode: configuration.themeMode,
            initialAccentColor: configuration.accentColor,
            themePreferenceStore: configuration.themePreferenceStore,
            initializeServicesAfterFirstFrame:
                NotificationService.instance.initialize,
          );
        }

        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
          theme: buildLightTheme(),
          home: _StartupErrorScreen(onRetry: _retryInitialization),
        );
        }

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(),
          home: StartupLoadingScreen(),
        );
      },
    );
  }
}

class StartupLoadingScreen extends StatelessWidget {
  const StartupLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          semanticsLabel: 'Loading Total Reminders',
        ),
      ),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Smaraṇa could not finish loading.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<_AppStartupConfiguration> _initializeApplication() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    const themePreferenceStore = ThemePreferenceStore();
    late final ThemeMode themeMode;
    late final Color accentColor;

    await Future.wait<void>([
      themePreferenceStore.loadThemeMode().then<void>((value) {
        themeMode = value;
      }),
      themePreferenceStore.loadAccentColor().then<void>((value) {
        accentColor = value;
      }),
    ]);
    return _AppStartupConfiguration(
      themeMode: themeMode,
      accentColor: accentColor,
      themePreferenceStore: themePreferenceStore,
    );
  } on Object catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'app startup',
      ),
    );
    rethrow;
  }
}

class _AppStartupConfiguration {
  const _AppStartupConfiguration({
    required this.themeMode,
    required this.accentColor,
    required this.themePreferenceStore,
  });

  final ThemeMode themeMode;
  final Color accentColor;
  final ThemePreferenceStore themePreferenceStore;
}
