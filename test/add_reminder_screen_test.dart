import 'package:app_smarana/features/reminders/models/reminder.dart';
import 'package:app_smarana/features/reminders/screens/add_reminder_screen.dart';
import 'package:app_smarana/features/reminders/services/reminder_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_reminder_notification_scheduler.dart';

void main() {
  testWidgets('keeps advanced reminder controls collapsed initially', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = ReminderStorage(
      notificationScheduler: FakeReminderNotificationScheduler(),
    );

    await _openForm(tester, storage: storage);

    expect(find.byKey(const ValueKey('date-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('time-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('repeat-option-daily')), findsNothing);
    expect(find.byKey(const ValueKey('sound-option')), findsNothing);
    expect(find.byKey(const ValueKey('description-field')), findsNothing);
    expect(find.text('WHEN'), findsNothing);
    expect(find.text('ALERTS'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('repeat-field')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('repeat-option-daily')), findsOneWidget);

    final alertSection = find.byKey(const ValueKey('alert-section'));
    await tester.ensureVisible(alertSection);
    await tester.tap(alertSection);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('repeat-option-daily')), findsNothing);
    expect(find.byKey(const ValueKey('sound-option')), findsOneWidget);
  });

  testWidgets('dismisses keyboard on outside tap and when scrolling form', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = ReminderStorage(
      notificationScheduler: FakeReminderNotificationScheduler(),
    );

    await _openForm(tester, storage: storage);
    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'Reminder title',
    );
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tapAt(const Offset(10, 200));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(find.byKey(const ValueKey('title-field')));
    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'Reminder details',
    );
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('dismisses keyboard before opening form options', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = ReminderStorage(
      notificationScheduler: FakeReminderNotificationScheduler(),
    );

    await _openForm(tester, storage: storage);
    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'Reminder title',
    );
    expect(tester.testTextInput.isVisible, isTrue);

    final dateOption = find.byKey(const ValueKey('date-field'));
    await tester.ensureVisible(dateOption);
    await tester.tap(dateOption);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.byType(DatePickerDialog), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(find.byKey(const ValueKey('title-field')));
    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'Reminder title',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('alert-section')));
    await tester.tap(find.byKey(const ValueKey('alert-section')));
    await tester.pumpAndSettle();
    final vibrateSwitch = find.descendant(
      of: find.byKey(const ValueKey('vibrate-option')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(vibrateSwitch);
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.tap(vibrateSwitch);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('saves the requested fields and preserves edit metadata', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const soundChannel = MethodChannel('smarana/reminder_sounds');
    final previewedSoundUris = <String?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(soundChannel, (call) async {
          if (call.method == 'listAlarmSounds') {
            return [
              {'name': 'Morning Bell', 'uri': 'content://alarms/morning-bell'},
            ];
          }
          if (call.method == 'previewAlarmSound') {
            previewedSoundUris.add(
              (call.arguments as Map<Object?, Object?>)['uri'] as String?,
            );
          }
          return null;
        });
    final storage = ReminderStorage(
      notificationScheduler: FakeReminderNotificationScheduler(),
    );
    final selectedDate = DateTime(2030, 1, 15);

    await _openForm(tester, storage: storage, initialDate: selectedDate);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('title-field')))
          .controller!
          .text,
      '',
    );
    final titleField = tester.widget<TextField>(
      find.byKey(const ValueKey('title-field')),
    );
    expect(titleField.decoration?.hintText, 'Title');
    expect(find.byKey(const ValueKey('description-field')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'Dentist appointment',
    );
    final moreOptions = find.byKey(const ValueKey('more-options-section'));
    await tester.ensureVisible(moreOptions);
    await tester.tap(moreOptions);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('description-field')),
      'Bring the insurance card.',
    );
    final alertSection = find.byKey(const ValueKey('alert-section'));
    await tester.ensureVisible(alertSection);
    await tester.tap(alertSection);
    await tester.pumpAndSettle();
    final soundOption = find.byKey(const ValueKey('sound-option'));
    await tester.ensureVisible(soundOption);
    await tester.tap(soundOption);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Morning Bell').last);
    await tester.pumpAndSettle();
    expect(previewedSoundUris, ['content://alarms/morning-bell']);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final dateOption = find.byKey(const ValueKey('date-field'));
    await tester.ensureVisible(dateOption);
    await tester.tap(
      find.descendant(of: dateOption, matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('time-field')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final timeLabel = tester.widget<Text>(
      find
          .descendant(
            of: find.byKey(const ValueKey('time-field')),
            matching: find.byType(Text),
          )
          .last,
    );
    final localizations = MaterialLocalizations.of(
      tester.element(find.byType(AddReminderScreen)),
    );

    final notificationModeOption = find.byKey(
      const ValueKey('notification-mode-option'),
    );
    await tester.ensureVisible(notificationModeOption);
    await tester.tap(notificationModeOption);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notification only'));
    await tester.pumpAndSettle();

    final snoozeOption = find.byKey(const ValueKey('snooze-option'));
    await tester.ensureVisible(snoozeOption);
    expect(find.text('15 minutes'), findsAtLeastNWidgets(1));
    await tester.tap(snoozeOption);
    await tester.pumpAndSettle();
    for (final option in ['5 minutes', '10 minutes', 'Custom']) {
      expect(find.text(option), findsOneWidget);
    }
    expect(find.text('15 minutes'), findsAtLeastNWidgets(1));
    await tester.tap(find.text('10 minutes'));
    await tester.pumpAndSettle();
    expect(find.text('10 minutes'), findsOneWidget);

    final vibrateSwitch = find.descendant(
      of: find.byKey(const ValueKey('vibrate-option')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(vibrateSwitch);
    await tester.tap(vibrateSwitch);
    await tester.pumpAndSettle();

    await _saveForm(tester);

    final saved = (await storage.getReminders()).single;
    expect(saved.title, 'Dentist appointment');
    expect(saved.description, 'Bring the insurance card.');
    expect(saved.dateTime.year, selectedDate.year);
    expect(saved.dateTime.month, selectedDate.month);
    expect(saved.dateTime.day, selectedDate.day);
    expect(
      localizations.formatTimeOfDay(
        TimeOfDay(hour: saved.dateTime.hour, minute: saved.dateTime.minute),
      ),
      timeLabel.data,
    );
    expect(saved.recurrenceRule.type, RecurrenceType.none);
    expect(saved.soundName, 'Morning Bell');
    expect(saved.soundUri, 'content://alarms/morning-bell');
    expect(saved.notificationMode, ReminderNotificationMode.notificationOnly);
    expect(saved.vibrate, isFalse);
    expect(saved.snoozeDurationMinutes, 10);

    final recurring = saved.copyWith(
      recurrenceRule: const RecurrenceRule(
        type: RecurrenceType.weekly,
        dayOfWeek: DateTime.tuesday,
      ),
      enabled: false,
    );
    await storage.updateReminder(recurring);
    await _openForm(tester, storage: storage, reminder: recurring);
    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'Updated appointment',
    );
    await _saveForm(tester);

    final updated = (await storage.getReminders()).single;
    expect(updated.title, 'Updated appointment');
    expect(updated.dateTime, saved.dateTime);
    expect(updated.recurrenceRule.type, RecurrenceType.weekly);
    expect(updated.recurrenceRule.dayOfWeek, DateTime.tuesday);
    expect(updated.enabled, isFalse);
    expect(updated.notificationMode, ReminderNotificationMode.notificationOnly);
    expect(updated.soundName, 'Morning Bell');
    expect(updated.soundUri, 'content://alarms/morning-bell');
    expect(updated.vibrate, isFalse);
    expect(updated.snoozeDurationMinutes, 10);
  });

  testWidgets('saves custom snooze durations in hours and minutes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = ReminderStorage(
      notificationScheduler: FakeReminderNotificationScheduler(),
    );

    await _openForm(tester, storage: storage);
    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'Custom snooze reminder',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('alert-section')));
    await tester.tap(find.byKey(const ValueKey('alert-section')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('snooze-option')));
    await tester.tap(find.byKey(const ValueKey('snooze-option')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('snooze-custom-value')),
      '2',
    );
    await tester.tap(find.byKey(const ValueKey('snooze-custom-unit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hours').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('2 hours'), findsOneWidget);

    await _saveForm(tester);
    var saved = (await storage.getReminders()).single;
    expect(saved.snoozeDurationMinutes, 120);

    await _openForm(tester, storage: storage, reminder: saved);
    await tester.ensureVisible(find.byKey(const ValueKey('alert-section')));
    await tester.tap(find.byKey(const ValueKey('alert-section')));
    await tester.pumpAndSettle();
    expect(find.text('2 hours'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('snooze-option')));
    await tester.tap(find.byKey(const ValueKey('snooze-option')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('snooze-custom-value')),
      '45',
    );
    await tester.tap(find.byKey(const ValueKey('snooze-custom-unit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minutes').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('45 minutes'), findsOneWidget);

    await _saveForm(tester);
    saved = (await storage.getReminders()).single;
    expect(saved.snoozeDurationMinutes, 45);
  });

  testWidgets('offers only the repeat presets and custom weekdays', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = ReminderStorage(
      notificationScheduler: FakeReminderNotificationScheduler(),
    );

    await _openForm(
      tester,
      storage: storage,
      initialDate: DateTime(2030, 1, 15),
    );
    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'Recurring reminder',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.tap(find.byKey(const ValueKey('repeat-field')));
    await tester.pumpAndSettle();
    for (final label in ['Do not repeat', 'Daily', 'Custom']) {
      expect(find.text(label), findsAtLeastNWidgets(1));
    }
    for (final label in [
      'Weekdays',
      'Weekly',
      'Biweekly',
      'Monthly',
      'Yearly',
    ]) {
      expect(find.text(label), findsNothing);
    }

    final customOption = find.byKey(const ValueKey('repeat-option-custom'));
    await tester.ensureVisible(customOption);
    await tester.tap(customOption);
    await tester.pumpAndSettle();
    expect(find.text('On'), findsOneWidget);
    final intervalField = find.byKey(const ValueKey('repeat-interval-custom'));
    expect(intervalField, findsOneWidget);
    expect(find.byKey(const ValueKey('repeat-frequency-custom')), findsNothing);
    await tester.ensureVisible(intervalField);
    await tester.enterText(intervalField, '2');
    for (final weekday in [
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
      DateTime.saturday,
      DateTime.sunday,
    ]) {
      expect(find.byKey(ValueKey('weekday-$weekday')), findsOneWidget);
    }
    for (final weekday in [
      DateTime.monday,
      DateTime.wednesday,
      DateTime.friday,
    ]) {
      final weekdayChip = find.byKey(ValueKey('weekday-$weekday'));
      await tester.ensureVisible(weekdayChip);
      await tester.tap(weekdayChip);
    }
    final tuesdayChip = find.byKey(const ValueKey('weekday-2'));
    await tester.ensureVisible(tuesdayChip);
    await tester.tap(tuesdayChip);
    await tester.pumpAndSettle();
    final onDateChip = find.text('On date');
    await tester.ensureVisible(onDateChip);
    await tester.tap(onDateChip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('18').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final endDateButton = find.byKey(const ValueKey('repeat-end-date'));
    await tester.ensureVisible(endDateButton);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(
      find.textContaining('Every 2 weeks on Monday, Wednesday and Friday'),
      findsAtLeastNWidgets(1),
    );
    expect(find.textContaining('until'), findsAtLeastNWidgets(1));
    await _saveForm(tester);
    final saved = (await storage.getReminders()).single;
    expect(saved.recurrenceRule.type, RecurrenceType.weekly);
    expect(saved.recurrenceRule.interval, 2);
    expect(saved.recurrenceRule.weekdays, [
      DateTime.monday,
      DateTime.wednesday,
      DateTime.friday,
    ]);
    expect(saved.recurrenceRule.endDate, DateTime(2030, 1, 18));
  });

  testWidgets('custom repeat supports month intervals', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = ReminderStorage(
      notificationScheduler: FakeReminderNotificationScheduler(),
    );

    await _openForm(
      tester,
      storage: storage,
      initialDate: DateTime(2030, 1, 15),
    );
    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'Monthly reminder',
    );
    await tester.tap(find.byKey(const ValueKey('repeat-field')));
    await tester.pumpAndSettle();
    final customOption = find.byKey(const ValueKey('repeat-option-custom'));
    await tester.ensureVisible(customOption);
    await tester.tap(customOption);
    await tester.pumpAndSettle();

    final intervalField = find.byKey(const ValueKey('repeat-interval-custom'));
    await tester.ensureVisible(intervalField);
    await tester.enterText(intervalField, '3');
    final unitDropdown = find.byKey(const ValueKey('repeat-unit-custom'));
    await tester.ensureVisible(unitDropdown);
    await tester.tap(unitDropdown);
    await tester.pumpAndSettle();
    for (final unit in ['Days', 'Weeks', 'Months', 'Years']) {
      expect(find.text(unit), findsAtLeastNWidgets(1));
    }
    await tester.tap(find.text('Days').last);
    await tester.pumpAndSettle();
    expect(find.text('Every 3 days'), findsAtLeastNWidgets(1));

    await tester.ensureVisible(unitDropdown);
    await tester.tap(unitDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Years').last);
    await tester.pumpAndSettle();
    expect(find.text('Every 3 years'), findsAtLeastNWidgets(1));

    await tester.ensureVisible(unitDropdown);
    await tester.tap(unitDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Months').last);
    await tester.pumpAndSettle();

    expect(find.text('Every 3 months'), findsAtLeastNWidgets(1));
    expect(find.byKey(const ValueKey('weekday-1')), findsNothing);

    await _saveForm(tester);
    final saved = (await storage.getReminders()).single;
    expect(saved.recurrenceRule.type, RecurrenceType.monthly);
    expect(saved.recurrenceRule.interval, 3);
    expect(saved.recurrenceRule.dayOfMonth, 15);
    expect(saved.recurrenceRule.endDate, isNull);
  });
}

Future<void> _openForm(
  WidgetTester tester, {
  required ReminderStorage storage,
  Reminder? reminder,
  DateTime? initialDate,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey('open-form'),
            onPressed: () {
              Navigator.of(context).push<Reminder>(
                MaterialPageRoute(
                  builder: (_) => AddReminderScreen(
                    reminder: reminder,
                    storage: storage,
                    initialDate: initialDate,
                  ),
                ),
              );
            },
            child: const Text('Open form'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-form')));
  await tester.pumpAndSettle();
}

Future<void> _saveForm(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('save-reminder')));
  await tester.tap(find.byKey(const ValueKey('save-reminder')));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}
