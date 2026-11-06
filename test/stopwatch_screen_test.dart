import 'dart:convert';

import 'package:app_smarana/features/time_tools/stopwatch_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => const MaterialApp(
  home: StopwatchScreen(
    appMenu: SizedBox.shrink(),
    useInternalNavigationDrawer: false,
  ),
);

String _encoded({
  required int accumulatedMs,
  int? runningSinceMs,
  List<Map<String, int>> laps = const [],
}) => jsonEncode({
  'accumulatedMs': accumulatedMs,
  'runningSinceMs': runningSinceMs,
  'laps': laps,
});

void main() {
  testWidgets('shows a guidance hint on a fresh stopwatch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('stopwatch-empty-hint')),
      findsOneWidget,
    );
  });

  testWidgets('lap records split and total while paused', (tester) async {
    SharedPreferences.setMockInitialValues({
      'stopwatchState': _encoded(
        accumulatedMs: 5000,
        laps: [
          {'totalMs': 3000, 'splitMs': 3000},
        ],
      ),
    });
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('00:00:05.00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stopwatch-secondary-action')));
    await tester.pump();

    expect(find.text('Lap 2'), findsOneWidget);
    expect(find.text('Fastest · Total 00:00:05.00'), findsOneWidget);
    expect(find.text('00:00:02.00'), findsOneWidget);
    expect(find.text('Lap 1'), findsOneWidget);
    expect(find.text('Slowest · Total 00:00:03.00'), findsOneWidget);
  });

  testWidgets('restores a running stopwatch with time elapsed while closed', (
    tester,
  ) async {
    final runningSince = DateTime.now().subtract(const Duration(minutes: 1));
    SharedPreferences.setMockInitialValues({
      'stopwatchState': _encoded(
        accumulatedMs: 1000,
        runningSinceMs: runningSince.millisecondsSinceEpoch,
      ),
    });
    await tester.pumpWidget(_app());
    await tester.pump();

    final display = tester.widget<Text>(
      find.byKey(const ValueKey('stopwatch-display')),
    );
    expect(display.data, startsWith('00:01:0'));
    expect(find.text('Pause'), findsOneWidget);
  });

  testWidgets('labels the fastest and slowest laps by text and icon', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'stopwatchState': _encoded(
        accumulatedMs: 9000,
        laps: [
          {'totalMs': 9000, 'splitMs': 4000},
          {'totalMs': 5000, 'splitMs': 1000},
          {'totalMs': 3000, 'splitMs': 3000},
        ],
      ),
    });
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Slowest · Total 00:00:09.00'), findsOneWidget);
    expect(find.text('Fastest · Total 00:00:05.00'), findsOneWidget);
    expect(find.text('Total 00:00:03.00'), findsOneWidget);
    expect(find.byIcon(Icons.bolt), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_bottom), findsOneWidget);
  });

  testWidgets('does not label laps when all splits are equal', (tester) async {
    SharedPreferences.setMockInitialValues({
      'stopwatchState': _encoded(
        accumulatedMs: 4000,
        laps: [
          {'totalMs': 4000, 'splitMs': 2000},
          {'totalMs': 2000, 'splitMs': 2000},
        ],
      ),
    });
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Fastest · Total 00:00:04.00'), findsNothing);
    expect(find.text('Total 00:00:04.00'), findsOneWidget);
    expect(find.byIcon(Icons.bolt), findsNothing);
  });

  testWidgets('reset asks for confirmation and clears laps when confirmed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'stopwatchState': _encoded(
        accumulatedMs: 5000,
        laps: [
          {'totalMs': 5000, 'splitMs': 5000},
        ],
      ),
    });
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stopwatch-reset-action')));
    await tester.pumpAndSettle();
    expect(find.text('Reset stopwatch?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('stopwatch-display'))).data,
      '00:00:05.00',
    );
    expect(find.byKey(const ValueKey('stopwatch-laps')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stopwatch-reset-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stopwatch-reset-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('00:00:00.00'), findsOneWidget);
    expect(find.byKey(const ValueKey('stopwatch-laps')), findsNothing);
    final stored = (await SharedPreferences.getInstance()).getString(
      'stopwatchState',
    );
    expect(jsonDecode(stored!)['accumulatedMs'], 0);
  });

  testWidgets('starting persists the running state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stopwatch-primary-action')));
    await tester.pump();

    final stored = (await SharedPreferences.getInstance()).getString(
      'stopwatchState',
    );
    expect(jsonDecode(stored!)['runningSinceMs'], isNotNull);
  });

  testWidgets('malformed saved state is ignored safely', (tester) async {
    SharedPreferences.setMockInitialValues({'stopwatchState': '{broken json'});
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('00:00:00.00'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });
}
