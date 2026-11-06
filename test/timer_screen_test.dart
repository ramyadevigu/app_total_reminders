import 'dart:convert';

import 'package:app_smarana/features/time_tools/timer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('labeled timer shows the label and restores it', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(_timerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('timer-add')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('timer-preset-30')));
    await tester.tap(find.byKey(const ValueKey('timer-preset-30')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('timer-label-field')),
      '  Tea steeping  ',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('timer-save')));
    await tester.tap(find.byKey(const ValueKey('timer-save')));
    await tester.pumpAndSettle();

    expect(find.text('Tea steeping'), findsOneWidget);
    expect(find.text('30s timer'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_timerApp());
    await tester.pumpAndSettle();

    expect(find.text('Tea steeping'), findsOneWidget);
  });

  testWidgets('saves reusable timer cards and restores them', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(_timerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('timer-add')));
    await tester.pumpAndSettle();

    expect(find.text('30 sec'), findsOneWidget);
    expect(find.text('1m'), findsOneWidget);
    expect(find.text('5m'), findsOneWidget);
    expect(find.text('10m'), findsOneWidget);
    expect(find.text('30m'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('timer-preset-30')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timer-preset-30')));
    await tester.pumpAndSettle();
    expect(find.text('30'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('timer-save')));
    await tester.tap(find.byKey(const ValueKey('timer-save')));
    await tester.pumpAndSettle();

    expect(find.text('30s timer'), findsOneWidget);
    expect(find.text('00:30'), findsOneWidget);

    await tester.tap(find.byTooltip('Start 30s timer'));
    await tester.pump();
    expect(find.byTooltip('Pause 30s timer'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause 30s timer'));
    await tester.pump();
    expect(find.byTooltip('Start 30s timer'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_timerApp());
    await tester.pumpAndSettle();

    expect(find.text('30s timer'), findsOneWidget);
    expect(find.text('00:30'), findsOneWidget);
  });

  testWidgets('restores a running timer from its saved deadline', (
    tester,
  ) async {
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    SharedPreferences.setMockInitialValues({
      'savedTimers': jsonEncode([
        {
          'id': 'running-timer',
          'seconds': 300,
          'remainingMs': 300000,
          'running': true,
          'deadlineMs': deadline.millisecondsSinceEpoch,
          'finished': false,
        },
        {'id': 'bad-entry', 'seconds': 'not-a-number'},
      ]),
    });

    await tester.pumpWidget(_timerApp());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Pause 5m timer'), findsOneWidget);
    expect(find.text('5m timer'), findsOneWidget);
  });

  testWidgets('restores an expired running timer as finished', (tester) async {
    final deadline = DateTime.now().subtract(const Duration(minutes: 1));
    SharedPreferences.setMockInitialValues({
      'savedTimers': jsonEncode([
        {
          'id': 'expired-timer',
          'seconds': 60,
          'remainingMs': 60000,
          'running': true,
          'deadlineMs': deadline.millisecondsSinceEpoch,
          'finished': false,
        },
      ]),
    });

    await tester.pumpWidget(_timerApp());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Pause 1m timer'), findsNothing);
    expect(find.byTooltip('Restart 1m timer'), findsOneWidget);
  });

  testWidgets('finished timer offers restart and dismiss actions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'savedTimers': jsonEncode([
        {
          'id': 'done-timer',
          'seconds': 60,
          'remainingMs': 0,
          'running': false,
          'finished': true,
        },
      ]),
    });

    await tester.pumpWidget(_timerApp());
    await tester.pumpAndSettle();

    expect(find.text('Finished'), findsOneWidget);
    expect(find.byKey(const ValueKey('timer-card-dismiss-done-timer')), findsOneWidget);
    expect(find.byTooltip('Start 1m timer'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('timer-card-dismiss-done-timer')));
    await tester.pumpAndSettle();

    expect(find.text('Finished'), findsNothing);
    expect(find.text('01:00'), findsOneWidget);
    expect(find.byTooltip('Start 1m timer'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_timerApp());
    await tester.pumpAndSettle();
    expect(find.byTooltip('Start 1m timer'), findsOneWidget);
  });

  testWidgets('restart from finished state runs the full duration', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'savedTimers': jsonEncode([
        {
          'id': 'done-timer',
          'seconds': 60,
          'remainingMs': 0,
          'running': false,
          'finished': true,
        },
      ]),
    });

    await tester.pumpWidget(_timerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('timer-card-restart-done-timer')));
    await tester.pump();

    expect(find.text('Finished'), findsNothing);
    expect(find.byTooltip('Pause 1m timer'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause 1m timer'));
    await tester.pump();
  });

  testWidgets('skips malformed saved timer entries', (tester) async {

    SharedPreferences.setMockInitialValues({
      'savedTimers': jsonEncode([
        'not-a-map',
        {'id': 'zero', 'seconds': 0},
      ]),
    });

    await tester.pumpWidget(_timerApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('saved-timer-grid')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('alerts once when a running timer finishes live', (tester) async {
    final alerts = <String>[];
    final deadline = DateTime.now().add(const Duration(milliseconds: 400));
    SharedPreferences.setMockInitialValues({
      'savedTimers': jsonEncode([
        {
          'id': 'live-timer',
          'seconds': 1,
          'remainingMs': 400,
          'running': true,
          'deadlineMs': deadline.millisecondsSinceEpoch,
          'finished': false,
        },
      ]),
    });

    await tester.pumpWidget(
      _timerApp(onTimerFinished: (label) async => alerts.add(label)),
    );
    await tester.pumpAndSettle();
    expect(alerts, isEmpty);

    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(alerts, hasLength(1));
    expect(find.byTooltip('Restart 1s timer'), findsOneWidget);
  });

  testWidgets('does not alert for a timer that expired while app was closed', (
    tester,
  ) async {
    final alerts = <String>[];
    final deadline = DateTime.now().subtract(const Duration(minutes: 1));
    SharedPreferences.setMockInitialValues({
      'savedTimers': jsonEncode([
        {
          'id': 'expired-timer',
          'seconds': 60,
          'remainingMs': 60000,
          'running': true,
          'deadlineMs': deadline.millisecondsSinceEpoch,
          'finished': false,
        },
      ]),
    });

    await tester.pumpWidget(
      _timerApp(onTimerFinished: (label) async => alerts.add(label)),
    );
    await tester.pumpAndSettle();

    expect(alerts, isEmpty);
    expect(find.byTooltip('Restart 1m timer'), findsOneWidget);
  });
}

Widget _timerApp({Future<void> Function(String)? onTimerFinished}) {
  return MaterialApp(
    home: TimerScreen(
      appMenu: const SizedBox.shrink(),
      onTimerFinished: onTimerFinished,
    ),
  );
}
