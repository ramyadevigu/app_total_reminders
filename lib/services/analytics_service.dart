import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  AnalyticsService._();

  static final instance = AnalyticsService._();

  Future<void> logReminderCreated() => _logEvent('reminder_created');

  Future<void> logNoteCreated() => _logEvent('note_created');

  Future<void> _logEvent(String name) async {
    if (Firebase.apps.isEmpty) {
      return;
    }

    try {
      await FirebaseAnalytics.instance.logEvent(name: name);
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'Firebase Analytics',
          context: ErrorDescription('while logging "$name"'),
        ),
      );
    }
  }
}
