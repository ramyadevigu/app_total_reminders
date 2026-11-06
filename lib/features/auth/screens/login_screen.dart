import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_design_tokens.dart';
import '../services/google_auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onSignIn});

  final Future<void> Function()? onSignIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isSigningIn = false;
  String? _errorMessage;

  Future<void> _signIn() async {
    if (_isSigningIn) {
      return;
    }

    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });

    try {
      final signIn = widget.onSignIn;
      if (signIn != null) {
        await signIn();
      } else {
        await GoogleAuthService.instance.signInWithGoogle();
      }
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'Google sign-in',
        ),
      );
      if (mounted) {
        setState(() {
          _errorMessage = 'Sign-in could not be completed. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.lg,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight > AppSpacing.xl
                      ? constraints.maxHeight - AppSpacing.xl
                      : 0,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: AppMotion.resolve(context, AppMotion.screen),
                      curve: AppMotion.enter,
                      builder: (context, value, child) => Opacity(
                        opacity: value,
                        child: Transform.scale(
                          scale: 0.985 + (0.015 * value),
                          child: child,
                        ),
                      ),
                      child: _buildContent(context, colorScheme),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    final secondaryTextColor = colorScheme.onSurfaceVariant;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 480),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(height: AppSpacing.xs),
          Column(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.notifications_active_rounded,
                  size: 32,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Total Reminders',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Your reminders. Always with you.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: secondaryTextColor,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Welcome to Total Reminders',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.35,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Sign in to securely access your reminders and keep your '
                  'experience personalized.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(
                    color: secondaryTextColor,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                _GoogleSignInButton(
                  isSigningIn: _isSigningIn,
                  onPressed: _signIn,
                ),
                AnimatedSize(
                  duration: AppMotion.resolve(context, AppMotion.interaction),
                  curve: AppMotion.standard,
                  child: _errorMessage == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md),
                          child: Text(
                            _errorMessage!,
                            key: const ValueKey('login-error-message'),
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.error,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xs,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: secondaryTextColor,
                    ),
                    Text(
                      'Secure sign-in with Google',
                      style: textTheme.bodySmall?.copyWith(
                        color: secondaryTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'We never see or store your Google password.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              "By continuing, you agree to Total Reminders's Terms of Service "
              'and Privacy Policy.',
              textAlign: TextAlign.center,
              style: textTheme.labelSmall?.copyWith(
                color: secondaryTextColor,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({
    required this.isSigningIn,
    required this.onPressed,
  });

  final bool isSigningIn;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 54,
      child: OutlinedButton(
        key: const ValueKey('continue-with-google'),
        onPressed: isSigningIn ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: colorScheme.surfaceContainerLow,
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(color: colorScheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          elevation: 0.5,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSigningIn)
              SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              )
            else
              Semantics(
                image: true,
                label: 'Google',
                child: ExcludeSemantics(
                  child: CustomPaint(
                    size: Size.square(20),
                    painter: _GoogleMarkPainter(),
                  ),
                ),
              ),
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Text(
                'Continue with Google',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleMarkPainter extends CustomPainter {
  const _GoogleMarkPainter();

  static const _googleBlue = Color(0xFF4285F4);
  static const _googleRed = Color(0xFFEA4335);
  static const _googleYellow = Color(0xFFFBBC05);
  static const _googleGreen = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.37;
    final strokeWidth = size.width * 0.19;
    final ringBounds = Rect.fromCircle(center: center, radius: radius);
    final colors = [_googleRed, _googleYellow, _googleGreen, _googleBlue];
    final startAngles = <double>[-math.pi / 2, 0, math.pi / 2, math.pi];

    for (var i = 0; i < colors.length; i++) {
      canvas.drawArc(
        ringBounds,
        startAngles[i],
        math.pi / 2,
        false,
        Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt,
      );
    }

    canvas.drawRect(
      Rect.fromLTRB(
        center.dx - 0.2,
        center.dy - strokeWidth / 2,
        size.width - 0.1,
        center.dy + strokeWidth / 2,
      ),
      Paint()..color = _googleBlue,
    );
  }

  @override
  bool shouldRepaint(covariant _GoogleMarkPainter oldDelegate) => false;
}
