import 'package:flutter/widgets.dart';

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
  static const double huge = 48;
}

abstract final class AppRadius {
  static const double control = 12;
  static const double compactCard = 16;
  static const double card = 20;
  static const double section = 24;
  static const double modal = 28;
}

abstract final class AppElevation {
  static const double flat = 0;
  static const double subtle = 1;
  static const double floating = 3;
}

abstract final class AppMotion {
  static const Duration micro = Duration(milliseconds: 140);
  static const Duration interaction = Duration(milliseconds: 190);
  static const Duration component = Duration(milliseconds: 250);
  static const Duration screen = Duration(milliseconds: 300);
  static const Duration themeDuration = Duration(milliseconds: 220);
  static const Curve standard = Curves.easeInOutCubic;
  static const Curve enter = Curves.easeOutCubic;

  static Duration get theme =>
      WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .disableAnimations
      ? Duration.zero
      : themeDuration;

  static Duration resolve(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
