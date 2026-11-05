import 'dart:convert';

import 'package:app_smarana/features/my_day/my_day_screen.dart';
import 'package:app_smarana/features/notes/models/note_workspace_models.dart';
import 'package:app_smarana/features/notes/services/note_workspace_storage.dart';
import 'package:app_smarana/features/reminders/models/reminder.dart';
import 'package:app_smarana/features/reminders/services/reminder_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_reminder_notification_scheduler.dart';

void main() {
  testWidgets('My Day add task uses a circular add control', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = ReminderStorage(
      notificationScheduler: FakeReminderNotificationScheduler(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MyDayScreen(
          appMenu: const SizedBox.shrink(),
          navigationDrawer: const SizedBox.shrink(),
          storage: storage,
          clock: () => DateTime(2026, 10, 8, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final addButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('my-day-add-task')),
    );
    expect(addButton.style?.shape?.resolve({}), isA<CircleBorder>());
    expect(addButton.tooltip, 'Add a task');
  });

  testWidgets('completes and persists a daily task occurrence', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = ReminderStorage(
      notificationScheduler: FakeReminderNotificationScheduler(),
    );
    await storage.addReminder(
      Reminder(
        id: 'daily-task',
        title: 'Review plans',
        dateTime: DateTime(2026, 10, 7, 9),
        recurrenceRule: const RecurrenceRule(type: RecurrenceType.daily),
        createdAt: DateTime(2026, 10, 1),
      ),
    );
    final screen = MyDayScreen(
      appMenu: const SizedBox.shrink(),
      navigationDrawer: const SizedBox.shrink(),
      storage: storage,
      clock: () => DateTime(2026, 10, 8, 8),
    );

    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
    expect(find.text('Review plans'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect((await storage.getReminders()).single.isCompleted, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
    expect(find.text('Completed (1)'), findsOneWidget);
    await tester.tap(find.text('Completed (1)'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });

  testWidgets('completing a one-time reminder cancels its notification', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final scheduler = FakeReminderNotificationScheduler();
    final storage = ReminderStorage(notificationScheduler: scheduler);
    await storage.addReminder(
      Reminder(
        id: 'one-time-task',
        title: 'Send the proposal',
        dateTime: DateTime(2026, 10, 8, 14),
        createdAt: DateTime(2026, 10, 1),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MyDayScreen(
          appMenu: const SizedBox.shrink(),
          navigationDrawer: const SizedBox.shrink(),
          storage: storage,
          clock: () => DateTime(2026, 10, 8, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect((await storage.getReminders()).single.isCompleted, isTrue);
    expect(scheduler.operations.last, 'cancel:one-time-task');
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });

  testWidgets('overdue reminders can be carried to today', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = ReminderStorage(
      notificationScheduler: FakeReminderNotificationScheduler(),
    );
    await storage.addReminder(
      Reminder(
        id: 'overdue-task',
        title: 'Finish the draft',
        dateTime: DateTime(2026, 10, 7, 15),
        createdAt: DateTime(2026, 10, 1),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MyDayScreen(
          appMenu: const SizedBox.shrink(),
          navigationDrawer: const SizedBox.shrink(),
          storage: storage,
          clock: () => DateTime(2026, 10, 8, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Overdue'), findsOneWidget);
    await tester.tap(find.byTooltip('Task options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to today'));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect((await storage.getReminders()).single.dateTime.day, 8);
  });

  testWidgets('task reordering is persisted for the current day', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = ReminderStorage(
      notificationScheduler: FakeReminderNotificationScheduler(),
    );
    for (final reminder in [
      Reminder(
        id: 'first-task',
        title: 'First task',
        dateTime: DateTime(2026, 10, 8, 9),
        createdAt: DateTime(2026, 10, 1),
      ),
      Reminder(
        id: 'second-task',
        title: 'Second task',
        dateTime: DateTime(2026, 10, 8, 10),
        createdAt: DateTime(2026, 10, 1),
      ),
    ]) {
      await storage.addReminder(reminder);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: MyDayScreen(
          appMenu: const SizedBox.shrink(),
          navigationDrawer: const SizedBox.shrink(),
          storage: storage,
          clock: () => DateTime(2026, 10, 8, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.timedDrag(
      find.byIcon(Icons.drag_handle_rounded).at(1),
      const Offset(0, -100),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();

    final rawOrder = (await SharedPreferences.getInstance()).getString(
      'my_day_task_order_v1',
    );
    expect(rawOrder, isNotNull);
    final order = (jsonDecode(rawOrder!) as Map<String, dynamic>)['2026-10-8'];
    expect(order, ['second-task', 'first-task']);
  });

  testWidgets('note-linked reminders show their source and open the note', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime(2026, 10, 8);
    final workspaceStorage = NoteWorkspaceStorage();
    await workspaceStorage.saveWorkspace([
      Notebook(
        id: 'work-notebook',
        name: 'Work',
        iconType: NotebookIconType.work,
        notes: [
          NoteEntry(
            id: 'presentation-note',
            notebookId: 'work-notebook',
            title: 'Presentation',
            content: 'Prepare slides',
            createdAt: now,
            updatedAt: now,
            reminderId: 'presentation-reminder',
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    final storage = ReminderStorage(
      notificationScheduler: FakeReminderNotificationScheduler(),
    );
    await storage.addReminder(
      Reminder(
        id: 'presentation-reminder',
        title: 'Prepare presentation',
        dateTime: DateTime(2026, 10, 8, 18),
        createdAt: now,
      ),
    );
    String? openedNotebookId;
    NoteEntry? openedNote;

    await tester.pumpWidget(
      MaterialApp(
        home: MyDayScreen(
          appMenu: const SizedBox.shrink(),
          navigationDrawer: const SizedBox.shrink(),
          storage: storage,
          workspaceStorage: workspaceStorage,
          clock: () => DateTime(2026, 10, 8, 8),
          onNoteSelected: (notebookId, note) {
            openedNotebookId = notebookId;
            openedNote = note;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Notes · Work'), findsOneWidget);
    await tester.tap(find.text('Notes · Work'));
    expect(openedNotebookId, 'work-notebook');
    expect(openedNote?.id, 'presentation-note');
  });
}
