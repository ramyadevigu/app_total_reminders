import 'package:app_smarana/features/reminders/models/reminder.dart';
import 'package:app_smarana/features/reminders/reminders_screen.dart';
import 'package:app_smarana/features/reminders/services/reminder_storage.dart';
import 'package:app_smarana/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_reminder_notification_scheduler.dart';

void main() {
  testWidgets('enables and disables reminders from the reminder list', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final scheduler = FakeReminderNotificationScheduler();
    final storage = ReminderStorage(notificationScheduler: scheduler);
    await storage.addReminder(
      _reminder(
        id: 'toggle',
        title: 'Toggle reminder',
        dateTime: DateTime(2026, 10, 1, 9),
        enabled: false,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: RemindersScreen(storage: storage),
      ),
    );
    await _pumpFrames(tester);
    final reminderSwitch = find.byType(Switch);
    expect(tester.widget<Switch>(reminderSwitch).value, isFalse);
    final reminderCard = find.ancestor(
      of: find.byKey(const ValueKey('reminder-switch-toggle')),
      matching: find.byType(Card),
    );
    final lightColorScheme = lightTheme.colorScheme;
    final darkColorScheme = darkTheme.colorScheme;
    final lightEnabledCardColor = Color.alphaBlend(
      lightColorScheme.primary.withValues(alpha: 0.06),
      lightColorScheme.surfaceContainerLow,
    );
    final darkEnabledCardColor = Color.alphaBlend(
      darkColorScheme.primary.withValues(alpha: 0.06),
      darkColorScheme.surfaceContainerLow,
    );
    expect(
      tester.widget<Card>(reminderCard).color,
      lightColorScheme.surfaceContainerLow,
    );

    await tester.tap(reminderSwitch);
    await _pumpFrames(tester);
    expect((await storage.getReminders()).single.enabled, isTrue);
    expect(scheduler.scheduledReminders.keys, contains('toggle'));
    final enabledSwitch = tester.widget<Switch>(reminderSwitch);
    expect(enabledSwitch.value, isTrue);
    expect(enabledSwitch.activeTrackColor, lightColorScheme.primary);
    expect(enabledSwitch.activeThumbColor, lightColorScheme.onPrimary);
    expect(tester.widget<Card>(reminderCard).color, lightEnabledCardColor);

    await tester.pumpWidget(const SizedBox.shrink());
    final restartedStorage = ReminderStorage(notificationScheduler: scheduler);
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: RemindersScreen(storage: restartedStorage),
      ),
    );
    await _pumpFrames(tester);
    expect((await restartedStorage.getReminders()).single.enabled, isTrue);
    final darkEnabledSwitch = tester.widget<Switch>(reminderSwitch);
    expect(darkEnabledSwitch.value, isTrue);
    expect(darkEnabledSwitch.activeTrackColor, darkColorScheme.primary);
    expect(darkEnabledSwitch.activeThumbColor, darkColorScheme.onPrimary);
    expect(tester.widget<Card>(reminderCard).color, darkEnabledCardColor);

    await tester.tap(reminderSwitch);
    await _pumpFrames(tester);
    expect((await restartedStorage.getReminders()).single.enabled, isFalse);
    expect(tester.widget<Switch>(reminderSwitch).value, isFalse);
    expect(
      tester.widget<Card>(reminderCard).color,
      darkColorScheme.surfaceContainerLow,
    );
    expect(scheduler.scheduledReminders, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    final disabledRestartStorage = ReminderStorage(
      notificationScheduler: scheduler,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: RemindersScreen(storage: disabledRestartStorage),
      ),
    );
    await _pumpFrames(tester);
    expect(
      (await disabledRestartStorage.getReminders()).single.enabled,
      isFalse,
    );
    expect(tester.widget<Switch>(reminderSwitch).value, isFalse);
    expect(
      tester.widget<Card>(reminderCard).color,
      lightColorScheme.surfaceContainerLow,
    );
  });

  testWidgets(
    'displays reminders and refreshes after create, edit, and delete',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = ReminderStorage(
        notificationScheduler: FakeReminderNotificationScheduler(),
      );
      await storage.saveReminders([
        _reminder(
          id: 'weekly',
          title: 'Weekly check-in',
          dateTime: DateTime(2026, 9, 28, 8),
          recurrenceRule: const RecurrenceRule(
            type: RecurrenceType.weekly,
            dayOfWeek: DateTime.monday,
          ),
          description: 'Call the team',
        ),
        _reminder(
          id: 'monthly',
          title: 'Monthly report',
          dateTime: DateTime(2026, 10, 3, 9, 30),
          recurrenceRule: const RecurrenceRule(
            type: RecurrenceType.monthly,
            dayOfMonth: 3,
          ),
        ),
        _reminder(
          id: 'yearly',
          title: 'Annual review',
          dateTime: DateTime(2026, 10, 15, 9, 30),
          recurrenceRule: const RecurrenceRule(type: RecurrenceType.yearly),
        ),
        _reminder(
          id: 'disabled',
          title: 'Disabled one-time',
          dateTime: DateTime(2026, 10, 16, 11),
          enabled: false,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(home: RemindersScreen(storage: storage)),
      );
      await _pumpFrames(tester);

      expect(find.text('Weekly check-in'), findsOneWidget);
      expect(find.text('8:00'), findsOneWidget);
      expect(find.text('AM'), findsWidgets);
      expect(find.text('Call the team'), findsOneWidget);
      expect(find.text('Every Monday'), findsOneWidget);
      expect(find.text('3rd of every month'), findsOneWidget);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -240));
      await _pumpFrames(tester);
      expect(find.text('Disabled'), findsOneWidget);

      await tester.tap(find.byTooltip('Add reminder'));
      await _pumpFrames(tester);
      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'New reminder',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('save-reminder')));
      await tester.tap(find.byKey(const ValueKey('save-reminder')));
      await _pumpFrames(tester);
      await _pumpFrames(tester);

      expect(find.text('New reminder'), findsOneWidget);
      expect(
        (await storage.getReminders())
            .singleWhere((reminder) => reminder.title == 'New reminder')
            .description,
        isNull,
      );
      expect(await storage.getReminders(), hasLength(5));

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -240));
      await _pumpFrames(tester);
      await tester.tap(find.text('New reminder'));
      await _pumpFrames(tester);
      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Edited reminder',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('save-reminder')));
      await tester.tap(find.byKey(const ValueKey('save-reminder')));
      await _pumpFrames(tester);
      await _pumpFrames(tester);

      expect(find.text('New reminder'), findsNothing);
      expect(find.text('Edited reminder'), findsOneWidget);
      expect(await storage.getReminders(), hasLength(5));

      final editedReminderId = (await storage.getReminders())
          .singleWhere((reminder) => reminder.title == 'Edited reminder')
          .id;
      final reminderCard = find.ancestor(
        of: find.text('Edited reminder'),
        matching: find.byType(Card),
      );
      expect(reminderCard, findsOneWidget);
      final reminderMenu = find.descendant(
        of: reminderCard,
        matching: find.byKey(ValueKey('reminder-menu-$editedReminderId')),
      );
      await tester.tap(reminderMenu);
      await _pumpFrames(tester);
      await tester.tap(
        find.byKey(ValueKey('delete-reminder-$editedReminderId')),
      );
      await _pumpFrames(tester);

      expect(find.text('Delete reminder?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await _pumpFrames(tester);
      expect(find.text('Edited reminder'), findsOneWidget);

      await tester.tap(reminderMenu);
      await _pumpFrames(tester);
      await tester.tap(
        find.byKey(ValueKey('delete-reminder-$editedReminderId')),
      );
      await _pumpFrames(tester);
      await tester.tap(find.text('Delete').last);
      await _pumpFrames(tester);

      expect(find.text('Edited reminder'), findsNothing);
      expect(await storage.getReminders(), hasLength(4));
      expect(
        (await storage.getReminders()).map((reminder) => reminder.id).toSet(),
        {'weekly', 'monthly', 'yearly', 'disabled'},
      );
    },
  );

  testWidgets('shows a designed empty state with an add action', (
    tester,
  ) async {
    final storage = _RecoveringReminderStorage()..shouldFail = false;
    await tester.pumpWidget(
      MaterialApp(home: RemindersScreen(storage: storage)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No reminders yet'), findsOneWidget);
    expect(find.text('Your reminders will appear here.'), findsOneWidget);
    expect(find.byTooltip('Add reminder'), findsOneWidget);
    final addButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('reminders-empty-add')),
    );
    expect(addButton.style?.shape?.resolve({}), isA<CircleBorder>());
  });

  testWidgets('shows loading and recoverable error states', (tester) async {
    final storage = _RecoveringReminderStorage();
    await tester.pumpWidget(
      MaterialApp(home: RemindersScreen(storage: storage)),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await _pumpFrames(tester);
    expect(find.text('Unable to load reminders'), findsOneWidget);

    storage.shouldFail = false;
    await tester.tap(find.byKey(const ValueKey('retry-reminders')));
    await _pumpFrames(tester);

    expect(find.text('No reminders yet'), findsOneWidget);
  });
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

class _RecoveringReminderStorage extends ReminderStorage {
  bool shouldFail = true;

  @override
  Future<List<Reminder>> getReminders() async {
    if (shouldFail) {
      throw StateError('Read failed');
    }
    return [];
  }
}

Reminder _reminder({
  required String id,
  required String title,
  required DateTime dateTime,
  RecurrenceRule recurrenceRule = const RecurrenceRule(
    type: RecurrenceType.none,
  ),
  String? description,
  bool enabled = true,
}) {
  return Reminder(
    id: id,
    title: title,
    description: description,
    dateTime: dateTime,
    recurrenceRule: recurrenceRule,
    enabled: enabled,
    createdAt: DateTime(2026, 9, 1),
  );
}
