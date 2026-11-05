import 'dart:convert';

import 'package:app_smarana/features/notes/models/note_workspace_models.dart';
import 'package:app_smarana/features/notes/notes_screen.dart';
import 'package:app_smarana/features/notes/services/note_workspace_storage.dart';
import 'package:app_smarana/features/notes/theme/note_card_colors.dart';
import 'package:app_smarana/features/notes/widgets/notebook_list_tile.dart';
import 'package:app_smarana/features/notes/widgets/recent_note_card.dart';
import 'package:app_smarana/features/reminders/models/reminder.dart';
import 'package:app_smarana/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('note card surfaces are white in light mode and black in dark mode', () {
    expect(
      noteCardSurfaceColor(ThemeData.light(), NoteCardColor.pink),
      Colors.white,
    );
    expect(
      noteCardSurfaceColor(ThemeData.dark(), NoteCardColor.blue),
      Colors.black,
    );
  });

  testWidgets('Notes home starts in grid with persistent search and sorting', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime(2026, 10, 1);
    final notebook = Notebook(
      id: 'toolbar-notebook',
      name: 'Quick notes',
      iconType: NotebookIconType.general,
      notes: [
        for (final title in ['Zulu', 'Alpha'])
          NoteEntry(
            id: title.toLowerCase(),
            notebookId: 'toolbar-notebook',
            title: title,
            content: 'A note preview.',
            createdAt: now,
            updatedAt: now,
          ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(home: NotesScreen(initialNotebooks: [notebook])),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('notes-drawer-button')), findsOneWidget);
    expect(find.text('Search notes'), findsOneWidget);
    expect(find.byKey(const ValueKey('notes-grid-view')), findsOneWidget);
    expect(find.byKey(const ValueKey('notes-list-view')), findsNothing);
    final gridDelegate =
        tester
                .widget<GridView>(find.byKey(const ValueKey('notes-grid-view')))
                .gridDelegate
            as SliverGridDelegateWithFixedCrossAxisCount;
    expect(gridDelegate.crossAxisCount, 2);
    expect(gridDelegate.crossAxisSpacing, 6);
    expect(gridDelegate.mainAxisSpacing, 6);

    await tester.tap(find.byKey(const ValueKey('notes-view-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notes-list-view')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notes-sort-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('recent-note-card-alpha')))
          .dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('recent-note-card-zulu')))
            .dy,
      ),
    );
  });

  testWidgets(
    'Notes drawer filters labels and reaches app navigation actions',
    (tester) async {
      final now = DateTime(2026, 10, 1);
      final notebook = Notebook(
        id: 'labeled-notebook',
        name: 'Labeled notes',
        iconType: NotebookIconType.general,
        notes: [
          NoteEntry(
            id: 'labeled-note',
            notebookId: 'labeled-notebook',
            title: 'Shopping list',
            content: 'Milk and bread',
            projectMetadata: const NoteProjectMetadata(tags: ['Personal']),
            createdAt: now,
            updatedAt: now,
          ),
          NoteEntry(
            id: 'unlabeled-note',
            notebookId: 'labeled-notebook',
            title: 'Meeting notes',
            content: 'Project update',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      final visitedTabs = <int>[];
      var settingsOpened = false;
      var helpOpened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: NotesScreen(
            initialNotebooks: [notebook],
            onNavigateToTab: visitedTabs.add,
            onOpenSettings: () async => settingsOpened = true,
            onOpenHelp: () async => helpOpened = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('notes-drawer-button')));
      await tester.pumpAndSettle();
      expect(find.text('Total Reminders'), findsOneWidget);
      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Reminders'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('notes-drawer-label-personal')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('notes-drawer-label-personal')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shopping list'), findsOneWidget);
      expect(find.text('Meeting notes'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('notes-drawer-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notes-drawer-calendar')));
      await tester.pumpAndSettle();
      expect(visitedTabs, [0]);

      await tester.tap(find.byKey(const ValueKey('notes-drawer-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notes-drawer-reminders')));
      await tester.pumpAndSettle();
      expect(visitedTabs, [0, 2]);

      await tester.tap(find.byKey(const ValueKey('notes-drawer-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notes-drawer-settings')));
      await tester.pumpAndSettle();
      expect(settingsOpened, isTrue);

      await tester.tap(find.byKey(const ValueKey('notes-drawer-button')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -320));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('notes-drawer-help')),
      );
      await tester.tap(find.byKey(const ValueKey('notes-drawer-help')));
      await tester.pumpAndSettle();
      expect(helpOpened, isTrue);
    },
  );

  testWidgets('Notes drawer creates labels and opens Archive and Deleted', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: NotesScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('notes-drawer-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-drawer-create-label')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Ideas');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('No notes with the "Ideas" label.'), findsOneWidget);

    final savedWorkspace = jsonDecode(
      (await SharedPreferences.getInstance()).getString(
        'smarana_note_workspace_v1',
      )!,
    ) as Map;
    expect(savedWorkspace['tagColors'], contains('ideas'));

    await tester.tap(find.byKey(const ValueKey('notes-drawer-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-drawer-archive')));
    await tester.pumpAndSettle();
    expect(find.text('No archived notes.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notes-drawer-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-drawer-deleted')));
    await tester.pumpAndSettle();
    expect(find.text('Deleted notes will appear here.'), findsOneWidget);
  });

  testWidgets('Notes home hides notebook controls', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NotesScreen(initialNotebooks: [])),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('notes-notebook-selector')), findsNothing);
    expect(find.text('New notebook'), findsNothing);
  });

  testWidgets('quick create menu expands, lists actions, and closes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: NotesScreen(initialNotebooks: [])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('notes-add-note-fab')));
    await tester.pumpAndSettle();
    for (final label in ['Image', 'Drawing', 'Audio', 'List', 'Text']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byTooltip('Close quick create'), findsOneWidget);

    await tester.tap(find.byTooltip('Close quick create'));
    await tester.pumpAndSettle();
    expect(find.text('Image'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick create Text opens the editor without notebook controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: NotesScreen(initialNotebooks: [])),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-add-note-fab')));
    await tester.pumpAndSettle();
    expect(find.text('Text'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notes-quick-create-text')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('rich-note-title-field')), findsOneWidget);
    expect(find.textContaining('Notebook:'), findsNothing);
    expect(
      find.byKey(const ValueKey('rich-note-notebook-dropdown')),
      findsNothing,
    );
    expect(find.text('New notebook'), findsNothing);
    expect(find.byKey(const ValueKey('notebook-add-section')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick create List opens an unchecked checklist editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: NotesScreen(initialNotebooks: [])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('notes-add-note-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-quick-create-list')));
    await tester.pumpAndSettle();

    final editor = tester.widget<quill.QuillEditor>(
      find.byKey(const ValueKey('rich-note-content-editor')),
    );
    final operations = editor.controller.document.toDelta().toJson();
    expect(
      operations.any((operation) {
        final attributes = operation['attributes'];
        return attributes is Map && attributes['list'] == 'unchecked';
      }),
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('note-editor-back')));
    await tester.pumpAndSettle();
    expect(find.text('Untitled note'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new note saves without notebook controls', (tester) async {
    final storage = NoteWorkspaceStorage();
    final now = DateTime(2026, 10, 1);
    final quickNotes = Notebook(
      id: defaultNotebookId,
      name: defaultNotebookName,
      iconType: NotebookIconType.general,
      notes: const [],
      createdAt: now,
      updatedAt: now,
    );
    final work = Notebook(
      id: 'work-notebook',
      name: 'Work',
      iconType: NotebookIconType.work,
      notes: const [],
      createdAt: now,
      updatedAt: now,
    );
    await storage.saveWorkspace([quickNotes, work]);

    await tester.pumpWidget(
      MaterialApp(home: NotesScreen(workspaceStorage: storage)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-add-note-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-quick-create-text')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('rich-note-content-editor')),
      findsOneWidget,
    );
    expect(find.textContaining('Notebook:'), findsNothing);
    expect(
      find.byKey(const ValueKey('rich-note-notebook-dropdown')),
      findsNothing,
    );
    expect(find.text('New notebook'), findsNothing);

    final editor = tester.widget<quill.QuillEditor>(
      find.byKey(const ValueKey('rich-note-content-editor')),
    );
    editor.controller.document.insert(0, 'Transferred note');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-editor-back')));
    await tester.pumpAndSettle();

    final restored = await storage.loadWorkspace();
    final restoredQuickNotes = restored.singleWhere(
      (notebook) => notebook.id == defaultNotebookId,
    );
    final restoredWork = restored.singleWhere(
      (notebook) => notebook.id == work.id,
    );
    expect(restoredQuickNotes.notes.single.content, 'Transferred note');
    expect(restoredQuickNotes.notes.single.notebookId, defaultNotebookId);
    expect(restoredWork.notes, isEmpty);
  });

  testWidgets('starts with a real empty workspace instead of demo notes', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: NotesScreen()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    final emptyState = find.text('No notes yet. Create a note to get started.');
    expect(emptyState, findsOneWidget);
    expect(tester.widget<Text>(emptyState).textAlign, TextAlign.center);
    expect(
      find.ancestor(of: emptyState, matching: find.byType(Container)),
      findsNothing,
    );
    expect(
      find.ancestor(of: emptyState, matching: find.byType(Card)),
      findsNothing,
    );
    expect(find.text('Notebooks'), findsNothing);
    expect(find.byType(NotebookListTile), findsNothing);
    expect(find.text('Plans & Goals'), findsNothing);
    expect(find.text('Weekly Review'), findsNothing);
    final storedWorkspace = jsonDecode(
      (await SharedPreferences.getInstance()).getString(
        'smarana_note_workspace_v1',
      )!,
    ) as Map;
    final storedNotebooks = storedWorkspace['notebooks'] as List;
    expect(
      storedNotebooks.any(
        (notebook) => (notebook as Map)['name'] == defaultNotebookName,
      ),
      isTrue,
    );
  });

  testWidgets('home displays multicolor notes across theme modes and sizes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );

    final createdAt = DateTime(2026, 10, 1);
    final colors = NoteCardColor.values
        .where((color) => color != NoteCardColor.standard)
        .toList();
    final notebook = Notebook(
      id: 'palette-notebook',
      name: 'Colorful notes',
      iconType: NotebookIconType.ideas,
      notes: [
        for (final color in colors)
          NoteEntry(
            id: 'note-${color.name}',
            notebookId: 'palette-notebook',
            title: 'Palette ${color.name}',
            content: 'A note using the ${color.name} color.',
            color: color,
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
      ],
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    final cases = [
      (ThemeMode.light, Brightness.light, const Size(320, 640)),
      (ThemeMode.dark, Brightness.light, const Size(375, 812)),
      (ThemeMode.system, Brightness.light, const Size(800, 1024)),
      (ThemeMode.system, Brightness.dark, const Size(320, 640)),
    ];

    for (final (mode, systemBrightness, size) in cases) {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          systemBrightness;
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: mode,
          home: NotesScreen(initialNotebooks: [notebook]),
        ),
      );
      await tester.pumpAndSettle();

      final expectedBrightness = mode == ThemeMode.system
          ? systemBrightness
          : mode == ThemeMode.dark
          ? Brightness.dark
          : Brightness.light;
      expect(
        find.byKey(const ValueKey('notes-workspace-search')),
        findsOneWidget,
      );
      expect(
        Theme.of(
          tester.element(find.byKey(const ValueKey('notes-workspace-search'))),
        ).brightness,
        expectedBrightness,
      );

      final finalColorNote = find.text('Palette lavender');
      await tester.ensureVisible(finalColorNote);
      expect(finalColorNote, findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('opens notes directly without showing notebook labels', (
    tester,
  ) async {
    final notebook = Notebook(
      id: 'book-1',
      name: 'Engineering',
      iconType: NotebookIconType.work,
      notes: [
        NoteEntry(
          id: 'note-1',
          notebookId: 'book-1',
          title: 'Sprint Review',
          content: 'Document lessons learned.',
          createdAt: DateTime(2026, 9, 15),
          updatedAt: DateTime(2026, 9, 15, 10),
        ),
      ],
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 15),
    );

    await tester.pumpWidget(
      MaterialApp(home: NotesScreen(initialNotebooks: [notebook])),
    );

    await tester.tap(find.text('Sprint Review'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('rich-note-content-editor')),
      findsOneWidget,
    );
    expect(find.textContaining('Notebook:'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('note-editor-back')));
    await tester.pumpAndSettle();

    expect(find.text('Sprint Review'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recent-note-notebook-note-1')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('search filters all notes without a notebook selector', (
    tester,
  ) async {
    final notebooks = [
      Notebook(
        id: 'notebook-workout',
        name: 'Health & Fitness',
        iconType: NotebookIconType.health,
        notes: [
          NoteEntry(
            id: 'note-workout',
            notebookId: 'notebook-workout',
            title: 'Workout Split',
            content: 'Upper body, lower body, mobility, and recovery notes.',
            createdAt: DateTime(2026, 9, 29, 6, 30),
            updatedAt: DateTime(2026, 9, 29, 7, 5),
          ),
        ],
        createdAt: DateTime(2026, 8, 1, 9),
        updatedAt: DateTime(2026, 9, 29, 7, 5),
      ),
      Notebook(
        id: 'notebook-plans',
        name: 'Plans & Goals',
        iconType: NotebookIconType.goals,
        notes: [
          NoteEntry(
            id: 'note-plan',
            notebookId: 'notebook-plans',
            title: 'Weekly plan',
            content: 'Priorities for the week.',
            createdAt: DateTime(2026, 9, 29, 6, 30),
            updatedAt: DateTime(2026, 9, 29, 7, 5),
          ),
        ],
        createdAt: DateTime(2026, 8, 1, 9),
        updatedAt: DateTime(2026, 9, 1, 8),
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(home: NotesScreen(initialNotebooks: notebooks)),
    );

    expect(find.text('Notebooks'), findsNothing);
    expect(find.text('Workout Split'), findsOneWidget);
    expect(find.text('Weekly plan'), findsOneWidget);
    expect(find.byKey(const ValueKey('notes-notebook-selector')), findsNothing);
    expect(
      find.byKey(const ValueKey('recent-note-notebook-note-workout')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('notes-workspace-search')),
      'workout',
    );
    await tester.pump();

    expect(find.text('Health & Fitness'), findsNothing);
    expect(find.text('Plans & Goals'), findsNothing);
    expect(find.text('Workout Split'), findsOneWidget);
  });

  testWidgets('pins and unpins a note from the recent notes menu', (
    tester,
  ) async {
    final notebook = Notebook(
      id: 'book-pins',
      name: 'Ideas',
      iconType: NotebookIconType.ideas,
      notes: [
        NoteEntry(
          id: 'note-pin-target',
          notebookId: 'book-pins',
          title: 'Launch ideas',
          content: 'Collect the strongest campaign concepts.',
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 2),
        ),
      ],
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 2),
    );

    await tester.pumpWidget(
      MaterialApp(home: NotesScreen(initialNotebooks: [notebook])),
    );

    await tester.tap(find.byTooltip('Note actions for Launch ideas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin note'));
    await tester.pumpAndSettle();

    expect(find.text('Pinned'), findsNothing);
    expect(find.text('Launch ideas'), findsOneWidget);

    await tester.tap(find.byTooltip('Note actions for Launch ideas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unpin note'));
    await tester.pumpAndSettle();

    expect(find.text('Pinned'), findsNothing);
    expect(find.text('Launch ideas'), findsOneWidget);

    await tester.tap(find.text('Launch ideas'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rich-note-title-field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent notes remain without a heading or See all action', (
    tester,
  ) async {
    final now = DateTime.now();
    final notebook = Notebook(
      id: 'all-notes-notebook',
      name: 'Planning Notebook',
      iconType: NotebookIconType.general,
      notes: [
        for (var index = 0; index < 9; index++)
          NoteEntry(
            id: 'recent-note-$index',
            notebookId: 'all-notes-notebook',
            title: 'Recent planning note $index',
            content: 'A recent note for the home page.',
            createdAt: now.subtract(Duration(hours: index + 1)),
            updatedAt: now.subtract(Duration(hours: index + 1)),
          ),
        NoteEntry(
          id: 'older-note',
          notebookId: 'all-notes-notebook',
          title: 'Older planning note',
          content: 'This older note is still part of all notes.',
          createdAt: now.subtract(const Duration(days: 60)),
          updatedAt: now.subtract(const Duration(days: 45)),
        ),
      ],
      createdAt: now.subtract(const Duration(days: 60)),
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(home: NotesScreen(initialNotebooks: [notebook])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent Notes'), findsNothing);
    expect(find.text('See all'), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.text('Recent planning note 0'), findsOneWidget);
    expect(find.text('Older planning note'), findsOneWidget);
    await tester.tap(find.text('Recent planning note 0'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rich-note-title-field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'orders note cards by pin, recent update, reminder, then others',
    (tester) async {
      final now = DateTime.now();
      final reminder = Reminder(
        id: 'sort-reminder',
        title: 'Follow up',
        dateTime: now.add(const Duration(days: 2)),
        createdAt: now.subtract(const Duration(days: 60)),
      );
      SharedPreferences.setMockInitialValues({
        'reminders': jsonEncode([reminder.toJson()]),
      });

      final notebook = Notebook(
        id: 'sorting-notebook',
        name: 'Planning',
        iconType: NotebookIconType.general,
        notes: [
          NoteEntry(
            id: 'pinned-note',
            notebookId: 'sorting-notebook',
            title: 'Pinned note',
            content: 'Pinned',
            isPinned: true,
            createdAt: now.subtract(const Duration(days: 90)),
            updatedAt: now.subtract(const Duration(days: 60)),
          ),
          NoteEntry(
            id: 'updated-note',
            notebookId: 'sorting-notebook',
            title: 'Recently updated',
            content: 'Updated',
            createdAt: now.subtract(const Duration(days: 90)),
            updatedAt: now.subtract(const Duration(days: 1)),
          ),
          NoteEntry(
            id: 'reminder-note',
            notebookId: 'sorting-notebook',
            title: 'Reminder note',
            content: 'Reminder',
            reminderId: reminder.id,
            createdAt: now.subtract(const Duration(days: 90)),
            updatedAt: now.subtract(const Duration(days: 60)),
          ),
          NoteEntry(
            id: 'other-note',
            notebookId: 'sorting-notebook',
            title: 'Other note',
            content: 'Other',
            createdAt: now.subtract(const Duration(days: 90)),
            updatedAt: now.subtract(const Duration(days: 60)),
          ),
        ],
        createdAt: now.subtract(const Duration(days: 90)),
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(home: NotesScreen(initialNotebooks: [notebook])),
      );
      await tester.pumpAndSettle();

      final titles = tester
          .widgetList<RecentNoteCard>(find.byType(RecentNoteCard))
          .map((card) => card.note.note.title)
          .toList();
      expect(titles, [
        'Pinned note',
        'Recently updated',
        'Reminder note',
        'Other note',
      ]);
    },
  );

  testWidgets('updates note card color from its home card menu', (
    tester,
  ) async {
    final now = DateTime.now();
    final notebook = Notebook(
      id: 'color-notebook',
      name: 'Color tests',
      iconType: NotebookIconType.ideas,
      notes: [
        NoteEntry(
          id: 'color-note',
          notebookId: 'color-notebook',
          title: 'Color target',
          content: 'Change this note color.',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(home: NotesScreen(initialNotebooks: [notebook])),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Note actions for Color target'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change color'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-color-blue')));
    await tester.pumpAndSettle();

    final card = tester.widget<RecentNoteCard>(find.byType(RecentNoteCard));
    expect(card.note.note.color, NoteCardColor.blue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notes appear and disappear when added and deleted', (
    tester,
  ) async {
    final notebook = Notebook(
      id: 'book-create',
      name: 'Quick Ideas',
      iconType: NotebookIconType.ideas,
      notes: const [],
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 1),
    );

    await tester.pumpWidget(
      MaterialApp(home: NotesScreen(initialNotebooks: [notebook])),
    );
    expect(find.byType(RecentNoteCard), findsNothing);

    await tester.tap(find.byKey(const ValueKey('notes-add-note-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-quick-create-text')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rich-note-title-field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('rich-note-title-field')),
      'Campaign draft',
    );
    await tester.tap(find.byKey(const ValueKey('note-editor-back')));
    await tester.pumpAndSettle();

    expect(find.text('Campaign draft'), findsOneWidget);
    expect(find.byType(RecentNoteCard), findsOneWidget);

    await tester.tap(find.text('Campaign draft'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-editor-more-menu')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.byType(RecentNoteCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed note persistence is not shown as saved', (tester) async {
    final now = DateTime(2026, 10, 1);
    final workspaceStorage = _FailingNoteWorkspaceStorage(
      notebook: Notebook(
        id: defaultNotebookId,
        name: defaultNotebookName,
        iconType: NotebookIconType.general,
        notes: const [],
        createdAt: now,
        updatedAt: now,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: NotesScreen(workspaceStorage: workspaceStorage)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('notes-add-note-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-quick-create-text')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('rich-note-title-field')),
      'Unsaved draft',
    );
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();

    expect(find.text('Autosave failed'), findsOneWidget);
    expect(find.text('Saved'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _FailingNoteWorkspaceStorage extends NoteWorkspaceStorage {
  _FailingNoteWorkspaceStorage({required this.notebook});

  final Notebook notebook;

  @override
  Future<List<Notebook>> loadWorkspace() async => [notebook];

  @override
  Future<void> saveWorkspace(
    List<Notebook> notebooks, {
    Map<String, NoteCardColor>? tagColors,
  }) async {
    throw Exception('Simulated storage write failure');
  }
}
