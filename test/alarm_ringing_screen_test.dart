import 'package:app_smarana/features/reminders/models/reminder.dart';
import 'package:app_smarana/features/reminders/screens/alarm_ringing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const alarmChannel = MethodChannel('smarana/alarm_runtime');
  final methodCalls = <MethodCall>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(alarmChannel, (call) async {
          methodCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(alarmChannel, null);
  });

  testWidgets('shows alarm details and handles snooze and stop actions', (
    tester,
  ) async {
    final reminder = Reminder(
      id: 'morning-alarm',
      title: 'Wake up',
      description: 'Good Morning',
      dateTime: DateTime(2026, 10, 4, 7, 30),
      snoozeDurationMinutes: 120,
      createdAt: DateTime(2026, 10, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => AlarmRingingScreen(reminder: reminder),
                    ),
                  );
                },
                child: const Text('Open alarm'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open alarm'));
    await tester.pumpAndSettle();

    expect(find.text('ALARM'), findsOneWidget);
    expect(find.text('7:30 AM'), findsOneWidget);
    expect(find.text('Wake up'), findsOneWidget);
    expect(find.text('Good Morning'), findsOneWidget);
    expect(
      find.text(
        'If unanswered, this alarm snoozes automatically after '
        '5 minutes, then rings again in 2 hours.',
      ),
      findsOneWidget,
    );
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Snooze · 2 hrs'), findsOneWidget);

    await tester.tap(find.text('Snooze · 2 hrs'));
    await tester.pumpAndSettle();
    expect(methodCalls.last.method, 'snoozeAlarm');
    expect(find.text('Open alarm'), findsOneWidget);

    await tester.tap(find.text('Open alarm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(methodCalls.last.method, 'stopAlarm');
    expect(find.text('Open alarm'), findsOneWidget);
  });
}
