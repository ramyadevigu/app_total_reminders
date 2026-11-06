import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_design_tokens.dart';
import '../screens/login_screen.dart';
import '../services/google_auth_service.dart';

class AuthenticationGate extends StatefulWidget {
  const AuthenticationGate({
    super.key,
    required this.authenticatedChild,
    this.authenticationState,
  });

  final Widget authenticatedChild;
  final Stream<bool>? authenticationState;

  @override
  State<AuthenticationGate> createState() => _AuthenticationGateState();
}

class _AuthenticationGateState extends State<AuthenticationGate> {
  Stream<bool>? _authenticationState;

  @override
  void initState() {
    super.initState();
    _authenticationState = widget.authenticationState;
    if (_authenticationState == null && Firebase.apps.isNotEmpty) {
      _authenticationState = _createAuthenticationState();
    }
  }

  Stream<bool> _createAuthenticationState() =>
      widget.authenticationState ??
      GoogleAuthService.instance.authStateChanges.map((user) => user != null);

  void _retry() {
    setState(() => _authenticationState = _createAuthenticationState());
  }

  @override
  Widget build(BuildContext context) {
    final authenticationState = _authenticationState;
    if (authenticationState == null) {
      return widget.authenticatedChild;
    }

    return StreamBuilder<bool>(
      stream: authenticationState,
      builder: (context, snapshot) {
        final Widget screen;
        final String screenKey;
        if (snapshot.hasError) {
          screenKey = 'authentication-error';
          screen = _AuthenticationErrorScreen(onRetry: _retry);
        } else if (!snapshot.hasData) {
          screenKey = 'authentication-loading';
          screen = const _AuthenticationLoadingScreen();
        } else if (snapshot.data!) {
          screenKey = 'authenticated';
          screen = widget.authenticatedChild;
        } else {
          screenKey = 'login';
          screen = const LoginScreen();
        }

        return AnimatedSwitcher(
          duration: AppMotion.resolve(context, AppMotion.screen),
          switchInCurve: AppMotion.enter,
          switchOutCurve: Curves.easeInOut,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: KeyedSubtree(key: ValueKey(screenKey), child: screen),
        );
      },
    );
  }
}

class _AuthenticationLoadingScreen extends StatelessWidget {
  const _AuthenticationLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      key: ValueKey('authentication-loading-screen'),
      body: SafeArea(
        child: Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Checking sign-in status',
          ),
        ),
      ),
    );
  }
}

class _AuthenticationErrorScreen extends StatelessWidget {
  const _AuthenticationErrorScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('authentication-error-screen'),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 32),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Unable to check your sign-in status.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton(onPressed: onRetry, child: const Text('Try again')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
