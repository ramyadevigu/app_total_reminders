import 'package:shared_preferences/shared_preferences.dart';

import '../../calender/models/calendar_view_mode.dart';
import '../../reminders/models/reminder.dart';

class ReminderDefaults {
  const ReminderDefaults({
    this.notificationMode = ReminderNotificationMode.alarmAndNotification,
    this.soundUri,
    this.soundName = 'Default',
    this.snoozeDurationMinutes = 15,
    this.vibrate = true,
    this.calendarViewMode = CalendarViewMode.month,
  });

  final ReminderNotificationMode notificationMode;
  final String? soundUri;
  final String soundName;
  final int snoozeDurationMinutes;
  final bool vibrate;
  final CalendarViewMode calendarViewMode;

  ReminderDefaults copyWith({
    ReminderNotificationMode? notificationMode,
    String? soundUri,
    bool clearSoundUri = false,
    String? soundName,
    int? snoozeDurationMinutes,
    bool? vibrate,
    CalendarViewMode? calendarViewMode,
  }) {
    return ReminderDefaults(
      notificationMode: notificationMode ?? this.notificationMode,
      soundUri: clearSoundUri ? null : soundUri ?? this.soundUri,
      soundName: soundName ?? this.soundName,
      snoozeDurationMinutes:
          snoozeDurationMinutes ?? this.snoozeDurationMinutes,
      vibrate: vibrate ?? this.vibrate,
      calendarViewMode: calendarViewMode ?? this.calendarViewMode,
    );
  }
}

class ReminderPreferencesStore {
  const ReminderPreferencesStore();

  static const _notificationModeKey = 'defaultReminderNotificationMode';
  static const _soundUriKey = 'defaultReminderSoundUri';
  static const _soundNameKey = 'defaultReminderSoundName';
  static const _snoozeDurationKey = 'defaultReminderSnoozeDuration';
  static const _vibrateKey = 'defaultReminderVibrate';
  static const _calendarViewModeKey = 'calendarViewMode';

  Future<ReminderDefaults> loadDefaults() async {
    final preferences = await SharedPreferences.getInstance();
    final modeName = preferences.getString(_notificationModeKey);
    final notificationMode = ReminderNotificationMode.values.firstWhere(
      (mode) => mode.name == modeName,
      orElse: () => ReminderNotificationMode.alarmAndNotification,
    );
    final viewModeName = preferences.getString(_calendarViewModeKey);
    final calendarViewMode = switch (viewModeName) {
      'nextThreeDays' || 'threeDay' => CalendarViewMode.threeDay,
      'year' => CalendarViewMode.year,
      'week' => CalendarViewMode.week,
      'day' => CalendarViewMode.day,
      'list' => CalendarViewMode.list,
      _ => CalendarViewMode.month,
    };

    return ReminderDefaults(
      notificationMode: notificationMode,
      soundUri: preferences.getString(_soundUriKey),
      soundName: preferences.getString(_soundNameKey) ?? 'Default',
      snoozeDurationMinutes: _readSnoozeDuration(preferences),
      vibrate: preferences.getBool(_vibrateKey) ?? true,
      calendarViewMode: calendarViewMode,
    );
  }

  static int _readSnoozeDuration(SharedPreferences preferences) {
    final minutes = preferences.getInt(_snoozeDurationKey);
    return minutes != null && minutes > 0 ? minutes : 15;
  }

  Future<void> saveDefaults(ReminderDefaults defaults) async {
    final preferences = await SharedPreferences.getInstance();
    final results = await Future.wait([
      preferences.setString(
        _notificationModeKey,
        defaults.notificationMode.name,
      ),
      defaults.soundUri == null
          ? preferences.remove(_soundUriKey)
          : preferences.setString(_soundUriKey, defaults.soundUri!),
      preferences.setString(_soundNameKey, defaults.soundName),
      preferences.setInt(_snoozeDurationKey, defaults.snoozeDurationMinutes),
      preferences.setBool(_vibrateKey, defaults.vibrate),
      preferences.setString(
        _calendarViewModeKey,
        defaults.calendarViewMode.name,
      ),
    ]);
    if (results.any((saved) => !saved)) {
      throw StateError('Unable to save reminder defaults.');
    }
  }
}
