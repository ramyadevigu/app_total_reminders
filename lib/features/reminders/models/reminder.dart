enum RecurrenceType { none, daily, weekly, monthly, yearly }

enum ReminderNotificationMode { alarmAndNotification, notificationOnly }

class RecurrenceRule {
  final RecurrenceType type;

  /// Used for monthly recurrence.
  ///
  /// Example:
  /// 3 = 3rd day of every month.
  final int? dayOfMonth;

  /// Used for weekly recurrence.
  ///
  /// DateTime.monday = 1
  /// DateTime.tuesday = 2
  /// ...
  /// DateTime.sunday = 7
  final int? dayOfWeek;

  /// Repeats once every [interval] units of [type].
  final int interval;

  /// Selected weekdays for weekly recurrence, using DateTime weekday values.
  final List<int> weekdays;

  /// Used for yearly recurrence. January = 1, December = 12.
  final int? monthOfYear;

  /// The final date on which an occurrence may happen.
  final DateTime? endDate;

  const RecurrenceRule({
    required this.type,
    this.dayOfMonth,
    this.dayOfWeek,
    this.interval = 1,
    this.weekdays = const [],
    this.monthOfYear,
    this.endDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'dayOfMonth': dayOfMonth,
      'dayOfWeek': dayOfWeek,
      'interval': interval,
      'weekdays': weekdays,
      'monthOfYear': monthOfYear,
      'endDate': endDate?.toIso8601String(),
    };
  }

  factory RecurrenceRule.fromJson(Map<String, dynamic> json) {
    return RecurrenceRule(
      type: _recurrenceTypeFromJson(json['type']),
      dayOfMonth: _readInteger(json['dayOfMonth'], minimum: 1, maximum: 31),
      dayOfWeek: _readInteger(json['dayOfWeek'], minimum: 1, maximum: 7),
      interval: _readInteger(json['interval'], minimum: 1, maximum: 999) ?? 1,
      weekdays: _readWeekdays(json['weekdays']),
      monthOfYear: _readInteger(json['monthOfYear'], minimum: 1, maximum: 12),
      endDate: _dateTimeFromJson(json['endDate']),
    );
  }

  RecurrenceRule copyWith({
    RecurrenceType? type,
    int? dayOfMonth,
    int? dayOfWeek,
    int? interval,
    List<int>? weekdays,
    int? monthOfYear,
    DateTime? endDate,
  }) {
    return RecurrenceRule(
      type: type ?? this.type,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      interval: interval ?? this.interval,
      weekdays: weekdays ?? this.weekdays,
      monthOfYear: monthOfYear ?? this.monthOfYear,
      endDate: endDate ?? this.endDate,
    );
  }
}

class Reminder {
  final String id;
  final String title;
  final String? description;
  final DateTime dateTime;
  final RecurrenceRule recurrenceRule;
  final bool enabled;
  final bool isCompleted;
  final String? soundUri;
  final String soundName;
  final ReminderNotificationMode notificationMode;
  final bool vibrate;
  final int snoozeDurationMinutes;
  final DateTime? snoozedUntil;
  final DateTime createdAt;

  const Reminder({
    required this.id,
    required this.title,
    this.description,
    required this.dateTime,
    this.recurrenceRule = const RecurrenceRule(type: RecurrenceType.none),
    this.enabled = true,
    this.isCompleted = false,
    this.soundUri,
    this.soundName = 'Default',
    this.notificationMode = ReminderNotificationMode.alarmAndNotification,
    this.vibrate = true,
    this.snoozeDurationMinutes = 15,
    this.snoozedUntil,
    required this.createdAt,
  });

  Reminder copyWith({
    DateTime? dateTime,
    RecurrenceRule? recurrenceRule,
    bool? enabled,
    bool? isCompleted,
    String? soundUri,
    String? soundName,
    ReminderNotificationMode? notificationMode,
    bool? vibrate,
    int? snoozeDurationMinutes,
    DateTime? snoozedUntil,
    bool clearSnoozedUntil = false,
  }) {
    return Reminder(
      id: id,
      title: title,
      description: description,
      dateTime: dateTime ?? this.dateTime,
      recurrenceRule: recurrenceRule ?? this.recurrenceRule,
      enabled: enabled ?? this.enabled,
      isCompleted: isCompleted ?? this.isCompleted,
      soundUri: soundUri ?? this.soundUri,
      soundName: soundName ?? this.soundName,
      notificationMode: notificationMode ?? this.notificationMode,
      vibrate: vibrate ?? this.vibrate,
      snoozeDurationMinutes:
          snoozeDurationMinutes ?? this.snoozeDurationMinutes,
      snoozedUntil: clearSnoozedUntil
          ? null
          : snoozedUntil ?? this.snoozedUntil,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'dateTime': dateTime.toIso8601String(),
      'recurrenceRule': recurrenceRule.toJson(),
      'enabled': enabled,
      'isCompleted': isCompleted,
      'soundUri': soundUri,
      'soundName': soundName,
      'notificationMode': notificationMode.name,
      'vibrate': vibrate,
      'snoozeDurationMinutes': snoozeDurationMinutes,
      'snoozedUntil': snoozedUntil?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Reminder.fromJson(Map<String, dynamic> json) {
    final recurrenceJson = json['recurrenceRule'];
    final dateTime = _dateTimeFromJson(json['dateTime']) ?? DateTime(1970);
    final recurrenceRule = recurrenceJson is Map
        ? RecurrenceRule.fromJson(_stringKeyedMap(recurrenceJson))
        : RecurrenceRule(type: _recurrenceTypeFromJson(json['recurrence']));

    return Reminder(
      id: json['id'] is String ? json['id'] as String : '',
      title: json['title'] is String ? json['title'] as String : '',
      description: json['description'] is String
          ? json['description'] as String
          : null,
      dateTime: dateTime,
      recurrenceRule: recurrenceRule,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      isCompleted: json['isCompleted'] is bool
          ? json['isCompleted'] as bool
          : false,
      soundUri: json['soundUri'] is String ? json['soundUri'] as String : null,
      soundName: json['soundName'] is String
          ? json['soundName'] as String
          : 'Default',
      notificationMode: _notificationModeFromJson(json['notificationMode']),
      vibrate: json['vibrate'] is bool ? json['vibrate'] as bool : true,
      snoozeDurationMinutes:
          _readInteger(
            json['snoozeDurationMinutes'],
            minimum: 1,
            maximum: 1440,
          ) ??
          15,
      snoozedUntil: _dateTimeFromJson(json['snoozedUntil']),
      createdAt: _dateTimeFromJson(json['createdAt']) ?? dateTime,
    );
  }
}

ReminderNotificationMode _notificationModeFromJson(Object? value) {
  if (value is! String) {
    return ReminderNotificationMode.alarmAndNotification;
  }

  return ReminderNotificationMode.values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => ReminderNotificationMode.alarmAndNotification,
  );
}

RecurrenceType _recurrenceTypeFromJson(Object? value) {
  if (value is! String) {
    return RecurrenceType.none;
  }

  return RecurrenceType.values.firstWhere(
    (type) => type.name == value,
    orElse: () => RecurrenceType.none,
  );
}

int? _readInteger(Object? value, {required int minimum, required int maximum}) {
  if (value is! num || !value.isFinite || value != value.roundToDouble()) {
    return null;
  }

  final integer = value.toInt();
  return integer >= minimum && integer <= maximum ? integer : null;
}

List<int> _readWeekdays(Object? value) {
  if (value is! List) {
    return const [];
  }

  return value
      .whereType<num>()
      .where((day) => day.isFinite && day == day.roundToDouble())
      .map((day) => day.toInt())
      .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
      .toSet()
      .toList()
    ..sort();
}

DateTime? _dateTimeFromJson(Object? value) {
  return value is String ? DateTime.tryParse(value) : null;
}

Map<String, dynamic> _stringKeyedMap(Map<dynamic, dynamic> value) {
  return {
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}
