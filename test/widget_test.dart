// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_smarana/app/app.dart';
import 'package:app_smarana/features/calender/calender_screen.dart';
import 'package:app_smarana/features/notes/notes_screen.dart';
import 'package:app_smarana/features/my_day/my_day_screen.dart';
import 'package:app_smarana/features/reminders/reminders_screen.dart';
import 'package:app_smarana/features/time_tools/stopwatch_screen.dart';
import 'package:app_smarana/features/time_tools/timer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('global drawer navigates to My Day', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AppSmarana());
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.byKey(const ValueKey('global-navigation-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('navigation-myDay')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('navigation-myDay')));
    await tester.pumpAndSettle();

    expect(find.byType(MyDayScreen), findsOneWidget);
  });

  testWidgets('preserves tab state while switching destinations', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AppSmarana());

    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const ValueKey('nav-stopwatch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stopwatch-primary-action')));
    await tester.pump(const Duration(milliseconds: 120));

    await tester.tap(find.byKey(const ValueKey('nav-calendar')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byKey(const ValueKey('nav-stopwatch')));
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.text('Pause'), findsOneWidget);
  });

  testWidgets('app starts on the calendar screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'stopwatchState': jsonEncode({
        'accumulatedMs': 1000,
        'runningSinceMs': null,
        'laps': <Map<String, int>>[],
      }),
    });
    await tester.pumpWidget(const AppSmarana());

    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.byType(RemindersScreen), findsNothing);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    final destinations = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((destination) => destination.label)
        .toList();
    expect(destinations, [
      'Calendar',
      'Notes',
      'Alarms',
      'Stopwatch',
      'Timer',
    ]);
    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    final colorScheme = Theme.of(tester.element(find.byType(NavigationBar)))
        .colorScheme;
    expect(
      navigationBar.indicatorColor,
      colorScheme.primary.withValues(alpha: 0.12),
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.calendar_month)).color,
      colorScheme.primary,
    );
    for (final key in [
      'nav-calendar',
      'nav-notes',
      'nav-alarms',
      'nav-stopwatch',
      'nav-timer',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(find.text('World Clock'), findsNothing);

    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Help'), findsOneWidget);
    expect(find.text('Send Feedback'), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
    expect(find.byIcon(Icons.feedback_outlined), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-back-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('nav-notes')));
    await tester.pumpAndSettle();
    expect(find.byType(NotesScreen), findsOneWidget);
    expect(find.text('World Clock'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('nav-alarms')));
    await tester.pumpAndSettle();

    expect(find.byType(RemindersScreen), findsOneWidget);
    expect(find.text('Alarms'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('nav-stopwatch')));
    await tester.pumpAndSettle();
    expect(find.byType(StopwatchScreen), findsOneWidget);
    expect(find.text('00:00:01.00'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stopwatch-primary-action')));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Lap'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stopwatch-secondary-action')));
    await tester.pump();
    expect(find.byKey(const ValueKey('stopwatch-laps')), findsOneWidget);
    expect(find.text('Lap 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stopwatch-primary-action')));
    await tester.pump();
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stopwatch-reset-action')));
    await tester.pumpAndSettle();
    expect(find.text('Reset stopwatch?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stopwatch-reset-confirm')));
    await tester.pump();
    expect(find.text('00:00:00.00'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-timer')));
    await tester.pumpAndSettle();
    expect(find.byType(TimerScreen), findsOneWidget);
    expect(find.text('No saved timers'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('timer-add')));
    await tester.pumpAndSettle();
    for (final preset in [30, 60, 300, 600, 1800]) {
      expect(find.byKey(ValueKey('timer-preset-$preset')), findsOneWidget);
    }

    await tester.ensureVisible(find.byKey(const ValueKey('timer-preset-30')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timer-preset-30')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('timer-save')));
    await tester.tap(find.byKey(const ValueKey('timer-save')));
    await tester.pumpAndSettle();

    expect(find.text('30s timer'), findsOneWidget);
    expect(find.text('00:30'), findsOneWidget);
    await tester.tap(find.byTooltip('Start 30s timer'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byTooltip('Pause 30s timer'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause 30s timer'));
    await tester.pump();
    expect(find.byTooltip('Start 30s timer'), findsOneWidget);
  });
}
