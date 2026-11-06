import 'package:app_smarana/features/calender/services/calendar_service.dart';
import 'package:app_smarana/features/reminders/models/reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = CalendarService();

  test('projects single and recurring reminders into a date range', () {
    final reminders = [
      _reminder(
        id: 'monthly',
        title: 'Monthly',
        dateTime: DateTime(2026, 1, 31, 9),
        type: RecurrenceType.monthly,
        dayOfMonth: 31,
      ),
      _reminder(
        id: 'once',
        title: 'One-time',
        dateTime: DateTime(2026, 2, 28, 8),
      ),
      _reminder(
        id: 'daily',
        title: 'Daily',
        dateTime: DateTime(2026, 2, 27, 7),
        type: RecurrenceType.daily,
      ),
      _reminder(
        id: 'yearly',
        title: 'Yearly',
        dateTime: DateTime(2025, 2, 12, 7),
        type: RecurrenceType.yearly,
      ),
    ];

    final occurrences = service.occurrencesBetween(
      reminders,
      start: DateTime(2026, 2, 1),
      endExclusive: DateTime(2026, 3, 1),
    );

    expect(occurrences.keys, contains(DateTime(2026, 2, 27)));
    expect(occurrences.keys, contains(DateTime(2026, 2, 12)));
    expect(occurrences.keys, contains(DateTime(2026, 2, 28)));
    expect(
      occurrences[DateTime(2026, 2, 28)]!.map((item) => item.reminder.id),
      ['daily', 'once', 'monthly'],
    );
    expect(occurrences[DateTime(2026, 2, 27)]!.single.reminder.id, 'daily');
    expect(occurrences.keys, isNot(contains(DateTime(2026, 3, 1))));
  });

  test('projects supported recurrence intervals onto their calendar dates', () {
    final reminders = [
      _reminder(
        id: 'once',
        title: 'One-time',
        dateTime: DateTime(2026, 9, 4, 8),
      ),
      _reminder(
        id: 'daily',
        title: 'Daily',
        dateTime: DateTime(2026, 9, 2, 9),
        type: RecurrenceType.daily,
      ),
      _reminder(
        id: 'weekdays',
        title: 'Selected weekdays',
        dateTime: DateTime(2026, 9, 1, 10),
        type: RecurrenceType.weekly,
        weekdays: const [DateTime.tuesday, DateTime.thursday],
      ),
      _reminder(
        id: 'biweekly',
        title: 'Every two weeks',
        dateTime: DateTime(2026, 9, 1, 11),
        type: RecurrenceType.weekly,
        interval: 2,
        weekdays: const [DateTime.tuesday],
      ),
      _reminder(
        id: 'alternate-weeks',
        title: 'Alternate weeks',
        dateTime: DateTime(2026, 9, 2, 12),
        type: RecurrenceType.weekly,
        interval: 2,
        weekdays: const [DateTime.wednesday],
      ),
      _reminder(
        id: 'monthly',
        title: 'Monthly',
        dateTime: DateTime(2026, 9, 17, 13),
        type: RecurrenceType.monthly,
        dayOfMonth: 17,
      ),
      _reminder(
        id: 'alternate-months',
        title: 'Alternate months',
        dateTime: DateTime(2026, 9, 5, 14),
        type: RecurrenceType.monthly,
        interval: 2,
        dayOfMonth: 5,
      ),
      _reminder(
        id: 'yearly',
        title: 'Yearly',
        dateTime: DateTime(2025, 9, 10, 15),
        type: RecurrenceType.yearly,
        dayOfMonth: 10,
      ),
    ];

    final occurrences = service.occurrencesBetween(
      reminders,
      start: DateTime(2026, 9, 1),
      endExclusive: DateTime(2026, 12, 1),
    );

    expect(
      occurrences[DateTime(2026, 9, 1)]!.map((item) => item.reminder.id),
      contains('biweekly'),
    );
    expect(
      occurrences[DateTime(2026, 9, 2)]!.map((item) => item.reminder.id),
      contains('alternate-weeks'),
    );
    expect(
      occurrences[DateTime(2026, 9, 4)]!.map((item) => item.reminder.id),
      contains('once'),
    );
    expect(
      occurrences[DateTime(2026, 9, 15)]!.map((item) => item.reminder.id),
      contains('biweekly'),
    );
    expect(
      occurrences[DateTime(2026, 9, 17)]!.map((item) => item.reminder.id),
      contains('monthly'),
    );
    expect(
      occurrences[DateTime(2026, 11, 5)]!.map((item) => item.reminder.id),
      contains('alternate-months'),
    );
    final displayedIds = occurrences.values
        .expand((dayOccurrences) => dayOccurrences)
        .map((item) => item.reminder.id)
        .toSet();
    expect(displayedIds, containsAll(['daily', 'weekdays']));
  });

  test('filters Calendar occurrences by recurrence visibility', () {
    final reminders = [
      _reminder(
        id: 'one-time',
        title: 'One-time',
        dateTime: DateTime(2026, 10, 20, 8),
      ),
      _reminder(
        id: 'weekly',
        title: 'Weekly Monday',
        dateTime: DateTime(2026, 10, 5, 9),
        type: RecurrenceType.weekly,
        weekdays: const [DateTime.monday],
      ),
      _reminder(
        id: 'monthly',
        title: 'Monthly',
        dateTime: DateTime(2026, 10, 1, 10),
        type: RecurrenceType.monthly,
      ),
      _reminder(
        id: 'daily',
        title: 'Daily',
        dateTime: DateTime(2026, 10, 1, 11),
        type: RecurrenceType.daily,
      ),
      _reminder(
        id: 'twice-weekly',
        title: 'Monday and Thursday',
        dateTime: DateTime(2026, 10, 5, 12),
        type: RecurrenceType.weekly,
        weekdays: const [DateTime.monday, DateTime.thursday],
      ),
      _reminder(
        id: 'weekdays',
        title: 'Every weekday',
        dateTime: DateTime(2026, 10, 5, 13),
        type: RecurrenceType.weekly,
        weekdays: const [
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.thursday,
          DateTime.friday,
        ],
      ),
      _reminder(
        id: 'every-two-days',
        title: 'Every two days',
        dateTime: DateTime(2026, 10, 1, 14),
        type: RecurrenceType.daily,
        interval: 2,
      ),
      _reminder(
        id: 'every-two-weeks',
        title: 'Every two weeks',
        dateTime: DateTime(2026, 10, 5, 15),
        type: RecurrenceType.weekly,
        interval: 2,
        weekdays: const [DateTime.monday],
      ),
      _reminder(
        id: 'monthly-alarm',
        title: 'Monthly alarm',
        dateTime: DateTime(2026, 10, 3, 7),
        type: RecurrenceType.monthly,
        notificationMode: ReminderNotificationMode.alarmAndNotification,
      ),
      _reminder(
        id: 'daily-alarm',
        title: 'Daily alarm',
        dateTime: DateTime(2026, 10, 2, 7),
        type: RecurrenceType.daily,
        notificationMode: ReminderNotificationMode.alarmAndNotification,
      ),
    ];

    final occurrences = service.occurrencesBetween(
      reminders,
      start: DateTime(2026, 10, 1),
      endExclusive: DateTime(2026, 10, 29),
    );
    final displayedIds = occurrences.values
        .expand((dayOccurrences) => dayOccurrences)
        .map((item) => item.reminder.id)
        .toSet();

    expect(
      displayedIds,
      containsAll([
        'one-time',
        'weekly',
        'monthly',
        'daily',
        'twice-weekly',
        'weekdays',
        'every-two-days',
        'every-two-weeks',
        'monthly-alarm',
        'daily-alarm',
      ]),
    );
  });

  test('excludes disabled and completed reminders', () {
    final reminders = [
      _reminder(
        id: 'disabled',
        title: 'Disabled',
        dateTime: DateTime(2026, 9, 29, 9),
        enabled: false,
      ),
      _reminder(
        id: 'completed',
        title: 'Completed',
        dateTime: DateTime(2026, 9, 29, 10),
        isCompleted: true,
      ),
    ];

    expect(
      service.occurrencesBetween(
        reminders,
        start: DateTime(2026, 9, 1),
        endExclusive: DateTime(2026, 10, 1),
      ),
      isEmpty,
    );
  });
}

Reminder _reminder({
  required String id,
  required String title,
  required DateTime dateTime,
  RecurrenceType type = RecurrenceType.none,
  int interval = 1,
  int? dayOfMonth,
  List<int> weekdays = const [],
  bool enabled = true,
  bool isCompleted = false,
  ReminderNotificationMode notificationMode =
      ReminderNotificationMode.alarmAndNotification,
}) {
  return Reminder(
    id: id,
    title: title,
    dateTime: dateTime,
    recurrenceRule: RecurrenceRule(
      type: type,
      interval: interval,
      dayOfMonth: dayOfMonth,
      weekdays: weekdays,
    ),
    enabled: enabled,
    isCompleted: isCompleted,
    notificationMode: notificationMode,
    createdAt: DateTime(2026),
  );
}
