import 'package:app_smarana/features/reminders/models/reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes and deserializes reminder and recurrence configuration', () {
    final reminder = Reminder(
      id: 'reminder-id',
      title: 'Pay rent',
      description: 'Transfer the monthly payment',
      dateTime: DateTime(2026, 10, 3, 9, 30),
      recurrenceRule: const RecurrenceRule(
        type: RecurrenceType.monthly,
        dayOfMonth: 3,
      ),
      enabled: false,
      isCompleted: true,
      soundUri: 'content://alarms/tone/1',
      soundName: 'Morning Bell',
      notificationMode: ReminderNotificationMode.notificationOnly,
      vibrate: false,
      snoozeDurationMinutes: 15,
      snoozedUntil: DateTime(2026, 10, 3, 9, 45),
      createdAt: DateTime(2026, 9, 1, 12),
    );

    final decoded = Reminder.fromJson(reminder.toJson());

    expect(decoded.toJson(), reminder.toJson());
  });

  test('uses safe defaults for absent and malformed fields', () {
    final reminder = Reminder.fromJson({
      'id': 42,
      'title': null,
      'description': 3,
      'dateTime': 'not-a-date',
      'recurrenceRule': {
        'type': 'unknown',
        'dayOfMonth': 32,
        'dayOfWeek': 'Monday',
      },
      'enabled': 'yes',
      'isCompleted': 1,
      'createdAt': null,
    });

    expect(reminder.id, '');
    expect(reminder.title, '');
    expect(reminder.description, isNull);
    expect(reminder.dateTime, DateTime(1970));
    expect(reminder.recurrenceRule.type, RecurrenceType.none);
    expect(reminder.recurrenceRule.dayOfMonth, isNull);
    expect(reminder.recurrenceRule.dayOfWeek, isNull);
    expect(reminder.enabled, isTrue);
    expect(reminder.isCompleted, isFalse);
    expect(
      reminder.notificationMode,
      ReminderNotificationMode.alarmAndNotification,
    );
    expect(reminder.soundName, 'Default');
    expect(reminder.vibrate, isTrue);
    expect(reminder.snoozeDurationMinutes, 15);
    expect(reminder.snoozedUntil, isNull);
    expect(reminder.createdAt, DateTime(1970));
  });

  test('supports legacy recurrence type data', () {
    final reminder = Reminder.fromJson({
      'id': 'legacy-id',
      'title': 'Legacy reminder',
      'dateTime': '2026-09-28T08:00:00.000',
      'recurrence': 'weekly',
      'createdAt': '2026-09-20T10:00:00.000',
    });

    expect(reminder.recurrenceRule.type, RecurrenceType.weekly);
    expect(reminder.recurrenceRule.dayOfWeek, isNull);
    expect(reminder.enabled, isTrue);
    expect(reminder.recurrenceRule.interval, 1);
    expect(reminder.recurrenceRule.weekdays, isEmpty);
    expect(reminder.recurrenceRule.endDate, isNull);
  });

  test('persists complete custom recurrence configuration', () {
    final reminder = Reminder(
      id: 'custom-id',
      title: 'Weekday report',
      dateTime: DateTime(2026, 9, 28, 9),
      recurrenceRule: RecurrenceRule(
        type: RecurrenceType.weekly,
        interval: 2,
        weekdays: const [DateTime.monday, DateTime.wednesday, DateTime.friday],
        endDate: DateTime(2026, 12, 31),
      ),
      createdAt: DateTime(2026, 9, 1),
    );

    final decoded = Reminder.fromJson(reminder.toJson());

    expect(decoded.recurrenceRule.interval, 2);
    expect(decoded.recurrenceRule.weekdays, [1, 3, 5]);
    expect(decoded.recurrenceRule.endDate, DateTime(2026, 12, 31));
  });
}
