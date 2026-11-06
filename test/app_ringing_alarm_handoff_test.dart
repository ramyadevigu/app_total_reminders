import 'dart:async';

import 'package:app_smarana/app/app.dart';
import 'package:app_smarana/features/reminders/models/reminder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('opens the newer alarm when another alarm screen is active', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final ringingAlarmIds = StreamController<String>.broadcast();
    final stoppedAlarmIds = StreamController<String>.broadcast();
    var activeAlarmId = 'first-alarm';
    final reminders = [
      _reminder(id: 'first-alarm', title: 'First alarm'),
      _reminder(id: 'second-alarm', title: 'Second alarm'),
    ];

    await tester.pumpWidget(
      AppSmarana(
        ringingAlarmIds: ringingAlarmIds.stream,
        stoppedAlarmIds: stoppedAlarmIds.stream,
        readActiveAlarmReminderId: () async => activeAlarmId,
        loadAlarmReminders: () async => reminders,
      ),
    );

    ringingAlarmIds.add('first-alarm');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('First alarm'), findsOneWidget);

    activeAlarmId = 'second-alarm';
    ringingAlarmIds.add('second-alarm');
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Second alarm'), findsOneWidget);
    expect(find.text('First alarm'), findsNothing);

    stoppedAlarmIds.add('second-alarm');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Second alarm'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await ringingAlarmIds.close();
    await stoppedAlarmIds.close();
  });
}

Reminder _reminder({required String id, required String title}) {
  return Reminder(
    id: id,
    title: title,
    dateTime: DateTime(2026, 10, 14, 7),
    createdAt: DateTime(2026, 10, 1),
  );
}
