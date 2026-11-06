import 'package:app_smarana/features/reminders/models/reminder.dart';
import 'package:app_smarana/features/reminders/services/reminder_storage.dart';
import 'package:app_smarana/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'schedules alarm-mode reminders through the Android alarm runtime',
    () async {
      final notifications = _FakeNotificationPlatform();
      final alarms = _FakeRecurrenceAlarmPlatform();
      final alarmRuntime = _FakeAlarmRuntimePlatform();
      final service = _service(
        now: () => DateTime(2026, 9, 29, 8),
        notifications: notifications,
        alarms: alarms,
        alarmRuntime: alarmRuntime,
      );
      await service.initialize();
      final reminder = _reminder(
        'one-time',
        DateTime(2026, 9, 29, 9),
        RecurrenceType.none,
      );

      await service.scheduleReminder(reminder);

      expect(notifications.scheduled, isEmpty);
      expect(alarmRuntime.scheduled.values.single.dateTime, reminder.dateTime);
      expect(alarmRuntime.scheduled.values.single.reminder.id, reminder.id);
      expect(alarmRuntime.scheduled.values.single.reminder.soundUri, isNull);
      expect(alarmRuntime.scheduled.values.single.reminder.vibrate, isTrue);
      expect(alarmRuntime.scheduled.values.single.isSnooze, isFalse);
      expect(alarms.scheduled, isEmpty);
    },
  );

  test('timer completion alert uses the notification platform', () async {
    final notifications = _FakeNotificationPlatform();
    final service = _service(
      now: () => DateTime(2026, 9, 29, 8),
      notifications: notifications,
      alarms: _FakeRecurrenceAlarmPlatform(),
      alarmRuntime: _FakeAlarmRuntimePlatform(),
    );

    await service.showTimerFinished('5m');

    final alert = notifications.timerAlerts.single;
    expect(alert.title, 'Timer finished');
    expect(alert.body, '5m');
    expect(notifications.scheduled, isEmpty);
  });

  test(
    'notification-only reminders never use the selected alarm sound',
    () async {
      final notifications = _FakeNotificationPlatform();
      final alarmRuntime = _FakeAlarmRuntimePlatform();
      final service = _service(
        now: () => DateTime(2026, 9, 29, 8),
        notifications: notifications,
        alarms: _FakeRecurrenceAlarmPlatform(),
        alarmRuntime: alarmRuntime,
      );
      await service.initialize();
      final reminder =
          _reminder(
            'notification-only',
            DateTime(2026, 9, 29, 9),
            RecurrenceType.none,
          ).copyWith(
            soundUri: 'content://alarms/custom-tone',
            notificationMode: ReminderNotificationMode.notificationOnly,
            vibrate: false,
          );

      await service.scheduleReminder(reminder);

      final scheduled = notifications.scheduled.values.single;
      expect(scheduled.soundUri, isNull);
      expect(
        scheduled.notificationMode,
        ReminderNotificationMode.notificationOnly,
      );
      expect(scheduled.vibrate, isFalse);
      expect(alarmRuntime.scheduled, isEmpty);
    },
  );

  test('a persisted snooze is scheduled before the next recurrence', () async {
    final now = DateTime(2026, 9, 29, 8);
    final snoozedUntil = now.add(const Duration(minutes: 15));
    final notifications = _FakeNotificationPlatform();
    final alarms = _FakeRecurrenceAlarmPlatform();
    final alarmRuntime = _FakeAlarmRuntimePlatform();
    final service = _service(
      now: () => now,
      notifications: notifications,
      alarms: alarms,
      alarmRuntime: alarmRuntime,
    );
    await service.initialize();
    final reminder = _reminder(
      'snoozed-daily',
      DateTime(2026, 9, 28, 9),
      RecurrenceType.daily,
    ).copyWith(snoozedUntil: snoozedUntil);

    await service.scheduleReminder(reminder);

    expect(alarmRuntime.scheduled.values.single.dateTime, snoozedUntil);
    expect(alarmRuntime.scheduled.values.single.isSnooze, isTrue);
    expect(notifications.scheduled, isEmpty);
    expect(alarms.scheduled, isEmpty);
  });

  test('preserves a due native snooze during startup reconciliation', () async {
    final now = DateTime(2026, 9, 29, 8);
    final notifications = _FakeNotificationPlatform();
    final runtime = _FakeAlarmRuntimePlatform();
    final service = _service(
      now: () => now,
      notifications: notifications,
      alarms: _FakeRecurrenceAlarmPlatform(),
      alarmRuntime: runtime,
    );
    await service.initialize();
    final reminder = _reminder(
      'due-snooze',
      DateTime(2026, 9, 28, 9),
      RecurrenceType.daily,
    );

    await service.scheduleReminder(reminder);
    final id = runtime.scheduled.keys.single;
    runtime.pendingSnoozes[id] = now.subtract(const Duration(minutes: 1));

    await service.scheduleReminder(reminder);

    expect(
      runtime.scheduled[id]?.dateTime,
      now.add(const Duration(seconds: 1)),
    );
    expect(runtime.scheduled[id]?.isSnooze, isTrue);
  });

  test(
    'requests platform permissions during foreground initialization',
    () async {
      final notifications = _FakeNotificationPlatform();
      final alarmRuntime = _FakeAlarmRuntimePlatform();
      final service = _service(
        now: () => DateTime(2026, 9, 29, 8),
        notifications: notifications,
        alarms: _FakeRecurrenceAlarmPlatform(),
        alarmRuntime: alarmRuntime,
      );

      await service.initialize();

      expect(notifications.permissionRequests, [true]);
      expect(alarmRuntime.permissionRequests, [true]);
    },
  );

  test(
    'distinct reminder IDs with the same hash get distinct schedules',
    () async {
      final notifications = _FakeNotificationPlatform();
      final alarmRuntime = _FakeAlarmRuntimePlatform();
      final service = _service(
        now: () => DateTime(2026, 9, 29, 8),
        notifications: notifications,
        alarms: _FakeRecurrenceAlarmPlatform(),
        alarmRuntime: alarmRuntime,
      );
      await service.initialize();
      final first = _reminder(
        '34fc4ed9ff04000368feade30b1638ed',
        DateTime(2026, 9, 29, 9),
        RecurrenceType.none,
      );
      final second = _reminder(
        '3c60bbb3b7d9c2c42ebec1f1d13d56c8',
        DateTime(2026, 9, 29, 10),
        RecurrenceType.none,
      );

      await service.scheduleReminder(first);
      await service.scheduleReminder(second);

      expect(notifications.scheduled, isEmpty);
      expect(alarmRuntime.scheduled, hasLength(2));
      expect(
        alarmRuntime.scheduled.values.map((scheduled) => scheduled.reminder.id),
        containsAll([first.id, second.id]),
      );

      await service.cancelReminder(second.id);
      expect(alarmRuntime.scheduled, hasLength(1));
      expect(alarmRuntime.scheduled.values.single.reminder.id, first.id);
    },
  );

  group('recurring notification scheduling', () {
    test('schedules the next daily occurrence', () async {
      await _expectNextOccurrence(
        now: DateTime(2026, 9, 29, 8),
        reminder: _reminder(
          'daily',
          DateTime(2026, 9, 28, 9, 30),
          RecurrenceType.daily,
        ),
        expected: DateTime(2026, 9, 29, 9, 30),
      );
    });

    test('schedules the next weekly occurrence', () async {
      await _expectNextOccurrence(
        now: DateTime(2026, 9, 29, 10),
        reminder: _reminder(
          'weekly',
          DateTime(2026, 9, 28, 9, 30),
          RecurrenceType.weekly,
          dayOfWeek: DateTime.monday,
        ),
        expected: DateTime(2026, 10, 5, 9, 30),
      );
    });

    test('schedules the next monthly occurrence', () async {
      await _expectNextOccurrence(
        now: DateTime(2026, 9, 29, 10),
        reminder: _reminder(
          'monthly',
          DateTime(2026, 9, 3, 9, 30),
          RecurrenceType.monthly,
          dayOfMonth: 3,
        ),
        expected: DateTime(2026, 10, 3, 9, 30),
      );
    });

    test(
      'schedules the next yearly occurrence across the year boundary',
      () async {
        await _expectNextOccurrence(
          now: DateTime(2026, 12, 31, 10),
          reminder: _reminder(
            'yearly',
            DateTime(2025, 12, 31, 9, 30),
            RecurrenceType.yearly,
          ),
          expected: DateTime(2027, 12, 31, 9, 30),
        );
      },
    );

    test(
      'rearms one monthly schedule at month end without duplicates',
      () async {
        var now = DateTime(2026, 1, 31, 9, 30);
        final notificationPlatform = _FakeNotificationPlatform();
        final alarmPlatform = _FakeRecurrenceAlarmPlatform();
        final service = _service(
          now: () => now,
          notifications: notificationPlatform,
          alarms: alarmPlatform,
        );
        await service.initialize();
        final reminder = _reminder(
          'last-month-day',
          DateTime(2026, 1, 31, 9, 30),
          RecurrenceType.monthly,
          dayOfMonth: 31,
        ).copyWith(notificationMode: ReminderNotificationMode.notificationOnly);

        await service.scheduleReminder(reminder);
        expect(
          notificationPlatform.scheduled.values.single.dateTime,
          DateTime(2026, 2, 28, 9, 30),
        );

        now = DateTime(2026, 2, 28, 9, 40);
        await service.scheduleReminder(reminder);

        expect(notificationPlatform.scheduled, hasLength(1));
        expect(alarmPlatform.scheduled, hasLength(1));
        expect(
          notificationPlatform.scheduled.values.single.dateTime,
          DateTime(2026, 3, 31, 9, 30),
        );
        expect(
          alarmPlatform.scheduled.values.single,
          DateTime(2026, 3, 31, 9, 30).add(const Duration(seconds: 10)),
        );
      },
    );
  });

  test(
    'startup reconciliation restores exactly one schedule after restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final reminder = _reminder(
        'restart',
        DateTime(2026, 10, 3, 9, 30),
        RecurrenceType.monthly,
        dayOfMonth: 3,
      );
      final disabledReminder = _reminder(
        'disabled-restart',
        DateTime(2026, 10, 3, 9, 30),
        RecurrenceType.monthly,
        dayOfMonth: 3,
      ).copyWith(enabled: false);
      final completedReminder = _reminder(
        'completed-restart',
        DateTime(2026, 10, 3, 9, 30),
        RecurrenceType.monthly,
        dayOfMonth: 3,
      ).copyWith(isCompleted: true);
      await ReminderStorage(
        notificationScheduler: _service(
          now: () => DateTime(2026, 9, 29, 10),
          notifications: _FakeNotificationPlatform(),
          alarms: _FakeRecurrenceAlarmPlatform(),
        ),
      ).saveReminders([reminder, disabledReminder, completedReminder]);

      final notifications = _FakeNotificationPlatform();
      final alarms = _FakeRecurrenceAlarmPlatform();
      final alarmRuntime = _FakeAlarmRuntimePlatform();
      final service = _service(
        now: () => DateTime(2026, 9, 29, 10),
        notifications: notifications,
        alarms: alarms,
        alarmRuntime: alarmRuntime,
      );
      await service.initialize();
      final restoredStorage = ReminderStorage(notificationScheduler: service);

      await restoredStorage.initialize();
      await restoredStorage.rescheduleAllReminders();
      await restoredStorage.rescheduleAllReminders();

      expect(notifications.scheduled, isEmpty);
      expect(alarms.scheduled, isEmpty);
      expect(alarmRuntime.scheduled, hasLength(1));
      expect(
        alarmRuntime.scheduled.values.single.dateTime,
        DateTime(2026, 10, 3, 9, 30),
      );
    },
  );

  test(
    'disabled, edited, and deleted reminders replace or cancel schedules',
    () async {
      SharedPreferences.setMockInitialValues({});
      final notifications = _FakeNotificationPlatform();
      final alarms = _FakeRecurrenceAlarmPlatform();
      final alarmRuntime = _FakeAlarmRuntimePlatform();
      final service = _service(
        now: () => DateTime(2026, 9, 29, 8),
        notifications: notifications,
        alarms: alarms,
        alarmRuntime: alarmRuntime,
      );
      await service.initialize();
      final storage = ReminderStorage(notificationScheduler: service);
      final reminder = _reminder(
        'lifecycle',
        DateTime(2026, 9, 28, 9, 30),
        RecurrenceType.daily,
      );

      await storage.addReminder(reminder);
      await storage.updateReminder(
        _reminder(
          'lifecycle',
          DateTime(2026, 9, 28, 9, 30),
          RecurrenceType.daily,
          title: 'Edited reminder',
        ),
      );
      expect(alarmRuntime.scheduled, hasLength(1));
      expect(
        alarmRuntime.scheduled.values.single.reminder.title,
        'Edited reminder',
      );

      await storage.updateReminder(
        _reminder(
          'lifecycle',
          DateTime(2026, 9, 28, 9, 30),
          RecurrenceType.daily,
          enabled: false,
        ),
      );
      expect(alarmRuntime.scheduled, isEmpty);
      expect(alarms.scheduled, isEmpty);
      expect(await storage.getReminders(), hasLength(1));

      await storage.updateReminder(reminder);
      expect(alarmRuntime.scheduled, hasLength(1));
      expect(alarms.scheduled, isEmpty);

      await storage.deleteReminder('lifecycle');
      expect(notifications.scheduled, isEmpty);
      expect(alarmRuntime.scheduled, isEmpty);
      expect(alarms.scheduled, isEmpty);
      expect(await storage.getReminders(), isEmpty);
    },
  );
}

Future<void> _expectNextOccurrence({
  required DateTime now,
  required Reminder reminder,
  required DateTime expected,
}) async {
  final notifications = _FakeNotificationPlatform();
  final alarms = _FakeRecurrenceAlarmPlatform();
  final service = _service(
    now: () => now,
    notifications: notifications,
    alarms: alarms,
  );
  await service.initialize();

  await service.scheduleReminder(
    reminder.copyWith(
      notificationMode: ReminderNotificationMode.notificationOnly,
    ),
  );

  expect(notifications.scheduled.values.single.dateTime, expected);
  expect(
    alarms.scheduled.values.single,
    expected.add(const Duration(seconds: 10)),
  );
}

NotificationService _service({
  required DateTime Function() now,
  required _FakeNotificationPlatform notifications,
  required _FakeRecurrenceAlarmPlatform alarms,
  _FakeAlarmRuntimePlatform? alarmRuntime,
}) {
  return NotificationService.forTesting(
    notificationPlatform: notifications,
    recurrenceAlarmPlatform: alarms,
    alarmRuntimePlatform: alarmRuntime,
    isAndroid: true,
    now: now,
    localTimezone: () async => 'Etc/UTC',
  );
}

Reminder _reminder(
  String id,
  DateTime dateTime,
  RecurrenceType recurrenceType, {
  String? title,
  bool enabled = true,
  int? dayOfMonth,
  int? dayOfWeek,
}) {
  return Reminder(
    id: id,
    title: title ?? id,
    dateTime: dateTime,
    recurrenceRule: RecurrenceRule(
      type: recurrenceType,
      dayOfMonth: dayOfMonth,
      dayOfWeek: dayOfWeek,
    ),
    enabled: enabled,
    createdAt: DateTime(2026, 9, 1),
  );
}

class _FakeNotificationPlatform implements NotificationPlatform {
  final scheduled = <int, _ScheduledNotification>{};
  final timerAlerts = <_TimerAlert>[];
  final permissionRequests = <bool>[];

  @override
  Future<bool> initialize({required bool requestPermissions}) async {
    permissionRequests.add(requestPermissions);
    return true;
  }

  @override
  Future<void> schedule({
    required int id,
    required DateTime dateTime,
    required String title,
    required String? body,
    required String payload,
    required bool exactAlarmAllowed,
    required String? soundUri,
    required ReminderNotificationMode notificationMode,
    required bool vibrate,
  }) async {
    scheduled[id] = _ScheduledNotification(
      dateTime: dateTime,
      title: title,
      payload: payload,
      soundUri: soundUri,
      notificationMode: notificationMode,
      vibrate: vibrate,
    );
  }

  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
  }

  @override
  Future<void> showTimerFinished({
    required int id,
    required String title,
    required String body,
  }) async {
    timerAlerts.add(_TimerAlert(id: id, title: title, body: body));
  }
}

class _TimerAlert {
  const _TimerAlert({required this.id, required this.title, required this.body});

  final int id;
  final String title;
  final String body;
}

class _FakeRecurrenceAlarmPlatform implements RecurrenceAlarmPlatform {
  final scheduled = <int, DateTime>{};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> schedule({
    required DateTime dateTime,
    required int id,
    required String reminderId,
    required bool exactAlarmAllowed,
  }) async {
    scheduled[id] = dateTime;
  }

  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
  }
}

class _FakeAlarmRuntimePlatform implements AlarmRuntimePlatform {
  final scheduled = <int, _ScheduledAlarm>{};
  final permissionRequests = <bool>[];
  final stopped = <int>[];
  final snoozed = <int>[];
  final pendingSnoozes = <int, DateTime>{};

  @override
  Stream<String> get ringingReminderIds => const Stream<String>.empty();

  @override
  Stream<String> get stoppedReminderIds => const Stream<String>.empty();

  @override
  Future<bool> initialize({required bool requestPermissions}) async {
    permissionRequests.add(requestPermissions);
    return true;
  }

  @override
  Future<void> schedule({
    required int id,
    required DateTime dateTime,
    required Reminder reminder,
    required bool isSnooze,
  }) async {
    scheduled[id] = _ScheduledAlarm(
      dateTime: dateTime,
      reminder: reminder,
      isSnooze: isSnooze,
    );
  }

  @override
  Future<DateTime?> pendingSnoozeTime(int id) async => pendingSnoozes[id];

  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
    pendingSnoozes.remove(id);
  }

  @override
  Future<void> stop(int id) async {
    stopped.add(id);
  }

  @override
  Future<void> snooze(int id) async {
    snoozed.add(id);
  }

  @override
  Future<String?> activeReminderId() async => null;
}

class _ScheduledAlarm {
  const _ScheduledAlarm({
    required this.dateTime,
    required this.reminder,
    required this.isSnooze,
  });

  final DateTime dateTime;
  final Reminder reminder;
  final bool isSnooze;
}

class _ScheduledNotification {
  const _ScheduledNotification({
    required this.dateTime,
    required this.title,
    required this.payload,
    required this.soundUri,
    required this.notificationMode,
    required this.vibrate,
  });

  final DateTime dateTime;
  final String title;
  final String payload;
  final String? soundUri;
  final ReminderNotificationMode notificationMode;
  final bool vibrate;
}
