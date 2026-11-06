import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/analytics_service.dart';
import '../../../services/notification_service.dart';
import '../models/reminder.dart';

class ReminderStorage {
  ReminderStorage({ReminderNotificationScheduler? notificationScheduler})
    : _notificationScheduler =
          notificationScheduler ?? NotificationService.instance;

  static const String _key = 'reminders';
  static final Map<Zone, Future<void>> _operationQueues = {};

  final ReminderNotificationScheduler _notificationScheduler;

  Future<void> initialize() async {
    await SharedPreferences.getInstance();
  }

  Future<List<Reminder>> getReminders() {
    return _runSerialized(_readReminders);
  }

  Future<void> saveReminders(List<Reminder> reminders) {
    return _runSerialized(() => _writeReminders(reminders));
  }

  Future<void> rescheduleAllReminders() async {
    final reminders = await getReminders();
    for (final reminder in reminders) {
      if (reminder.enabled && !reminder.isCompleted) {
        await _notificationScheduler.scheduleReminder(reminder);
      } else {
        await _notificationScheduler.cancelReminder(reminder.id);
      }
    }
  }

  Future<void> addReminder(Reminder reminder) {
    return _runSerialized(() async {
      if (reminder.id.isEmpty) {
        throw ArgumentError.value(reminder.id, 'reminder.id');
      }

      final reminders = await _readReminders();
      if (reminders.any((existing) => existing.id == reminder.id)) {
        throw StateError('A reminder with ID "${reminder.id}" already exists.');
      }

      reminders.add(reminder);
      await _writeReminders(reminders);
      unawaited(AnalyticsService.instance.logReminderCreated());
      await _scheduleIfNeeded(reminder);
    });
  }

  Future<void> updateReminder(Reminder reminder) {
    return _runSerialized(() async {
      final reminders = await _readReminders();
      final index = reminders.indexWhere((item) => item.id == reminder.id);

      if (index == -1) {
        return;
      }

      await _notificationScheduler.cancelReminder(reminder.id);
      reminders[index] = reminder;
      await _writeReminders(reminders);
      await _scheduleIfNeeded(reminder);
    });
  }

  Future<void> deleteReminder(String id) {
    return _runSerialized(() async {
      await _notificationScheduler.cancelReminder(id);
      final reminders = await _readReminders();
      reminders.removeWhere((reminder) => reminder.id == id);
      await _writeReminders(reminders);
    });
  }

  Future<void> _scheduleIfNeeded(Reminder reminder) async {
    if (reminder.enabled && !reminder.isCompleted) {
      await _notificationScheduler.scheduleReminder(reminder);
    }
  }

  Future<List<Reminder>> _readReminders() async {
    final preferences = await SharedPreferences.getInstance();
    final storedValue = preferences.get(_key);
    if (storedValue is! String || storedValue.isEmpty) {
      return [];
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(storedValue);
    } on FormatException {
      return [];
    }

    if (decoded is! List) {
      return [];
    }

    final reminders = <Reminder>[];
    final reminderIds = <String>{};
    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }

      final json = <String, dynamic>{
        for (final entry in item.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
      final reminder = Reminder.fromJson(json);
      if (reminder.id.isEmpty || !reminderIds.add(reminder.id)) {
        continue;
      }
      reminders.add(reminder);
    }

    return reminders;
  }

  Future<void> _writeReminders(List<Reminder> reminders) async {
    final reminderIds = <String>{};
    for (final reminder in reminders) {
      if (reminder.id.isEmpty) {
        throw ArgumentError.value(reminder.id, 'reminder.id');
      }
      if (!reminderIds.add(reminder.id)) {
        throw StateError('A reminder with ID "${reminder.id}" already exists.');
      }
    }

    final preferences = await SharedPreferences.getInstance();
    final jsonList = reminders.map((reminder) => reminder.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    final saved = await preferences.setString(_key, jsonString);
    if (!saved) {
      throw StateError('Unable to save reminders.');
    }
  }

  Future<T> _runSerialized<T>(Future<T> Function() operation) {
    final zone = Zone.current;
    final previous = _operationQueues[zone] ?? Future<void>.value();
    final result = previous.then((_) => operation());
    _operationQueues[zone] = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}
