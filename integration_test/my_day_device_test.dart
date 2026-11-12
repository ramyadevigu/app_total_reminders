import 'package:app_smarana/features/my_day/my_day_screen.dart';
import 'package:app_smarana/features/reminders/models/reminder.dart';
import 'package:app_smarana/features/reminders/services/reminder_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/helpers/fake_reminder_notification_scheduler.dart';

Widget _app(ReminderStorage storage) => MaterialApp(
  home: MyDayScreen(
    appMenu: const SizedBox.shrink(),
    navigationDrawer: const SizedBox.shrink(),
    storage: storage,
    clock: () => DateTime(2026, 10, 8, 9),
  ),
);

ReminderStorage _storage() =>
    ReminderStorage(notificationScheduler: FakeReminderNotificationScheduler());

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  testWidgets('empty state renders on device', (tester) async {
    await tester.pumpWidget(_app(_storage()));
    await tester.pumpAndSettle();
    expect(find.text("Let's create your first task"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completion persists and Board view keeps task data', (
    tester,
  ) async {
    final storage = _storage();
    await storage.addReminder(
      Reminder(
        id: 'device-task-1',
        title: 'Device task one',
        dateTime: DateTime(2026, 10, 8, 10),
        createdAt: DateTime(2026, 10, 1),
      ),
    );
    await storage.addReminder(
      Reminder(
        id: 'device-task-2',
        title: 'Device task two',
        dateTime: DateTime(2026, 10, 8, 11),
        createdAt: DateTime(2026, 10, 1),
      ),
    );

    await tester.pumpWidget(_app(storage));
    await tester.pumpAndSettle();
    expect(find.text('Device task one'), findsOneWidget);
    expect(find.text('Device task two'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_app(storage));
    await tester.pumpAndSettle();
    expect(find.text('Completed (1)'), findsOneWidget);

    await tester.tap(find.text('Board'));
    await tester.pumpAndSettle();
    expect(find.text('Device task two'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
