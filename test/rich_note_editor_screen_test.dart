import 'package:app_smarana/features/notes/models/note_workspace_models.dart';
import 'package:app_smarana/features/notes/models/rich_note_draft.dart';
import 'package:app_smarana/features/notes/screens/rich_note_editor_screen.dart';
import 'package:app_smarana/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the inline title without notebook controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildLightTheme(), home: RichNoteEditorScreen()),
    );
    await tester.pumpAndSettle();

    final titleField = tester.widget<TextField>(
      find.byKey(const ValueKey('rich-note-title-field')),
    );
    expect(titleField.controller?.text, '');
    expect(titleField.decoration?.hintText, 'Untitled');
    expect(titleField.style?.fontWeight, FontWeight.w700);
    expect(titleField.decoration?.filled, isFalse);
    expect(titleField.decoration?.border, InputBorder.none);
    expect(titleField.decoration?.enabledBorder, InputBorder.none);
    expect(titleField.decoration?.focusedBorder, InputBorder.none);
    expect(titleField.decoration?.disabledBorder, InputBorder.none);
    expect(titleField.decoration?.errorBorder, InputBorder.none);
    expect(titleField.decoration?.focusedErrorBorder, InputBorder.none);
    expect(find.text('Edit note'), findsNothing);
    expect(find.textContaining('Notebook:'), findsNothing);
    expect(
      find.byKey(const ValueKey('rich-note-notebook-dropdown')),
      findsNothing,
    );
    expect(find.text('General'), findsNothing);
    expect(
      find.byKey(const ValueKey('rich-note-formatting-toolbar')),
      findsOneWidget,
    );
    expect(find.byTooltip('Bold'), findsNothing);
    expect(find.byTooltip('Text formatting'), findsOneWidget);
    expect(find.byTooltip('Add to note'), findsOneWidget);
    expect(find.byTooltip('Heading'), findsNothing);
  });

  testWidgets('opens compact reminder settings from the bell', (tester) async {
    await tester.pumpWidget(MaterialApp(home: RichNoteEditorScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('note-editor-reminder-button')));
    await tester.pumpAndSettle();

    expect(find.text('Set Reminder'), findsOneWidget);
    expect(find.text('Date & Time'), findsOneWidget);
    expect(find.text('Repeat'), findsOneWidget);
    expect(find.text('Alert sound'), findsOneWidget);
    expect(find.text('Project Mode'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pin, archive, edited date, and back-dismiss use note state', (
    tester,
  ) async {
    final editedAt = DateTime(2026, 4, 5, 10);
    final note = NoteEntry(
      id: 'menu-state-note',
      notebookId: 'notebook',
      title: 'Menu state',
      content: '',
      createdAt: editedAt,
      updatedAt: editedAt,
    );
    bool? pinned;
    bool? archived;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => RichNoteEditorScreen(
                      note: note,
                      onPinChanged: (draft) async {
                        pinned = draft.isPinned;
                      },
                      onArchiveChanged: (draft) async {
                        archived = draft.isArchived;
                      },
                    ),
                  ),
                );
              },
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('note-editor-more-menu')));
    await tester.pumpAndSettle();
    final localizations = MaterialLocalizations.of(
      tester.element(find.byKey(const ValueKey('note-editor-more-menu'))),
    );
    expect(
      find.text('Edited ${localizations.formatShortDate(editedAt)}'),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('note-editor-pin-button')));
    await tester.pumpAndSettle();
    expect(pinned, isTrue);

    await tester.tap(find.byKey(const ValueKey('note-editor-archive-button')));
    await tester.pumpAndSettle();
    expect(archived, isTrue);
    expect(find.text('Open editor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor insert and more sheets expose their requested actions', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: RichNoteEditorScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('note-editor-insert-button')));
    await tester.pumpAndSettle();
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Add image'), findsOneWidget);
    expect(find.text('Recording'), findsOneWidget);
    expect(find.text('Drawing'), findsOneWidget);
    expect(find.text('Tick boxes'), findsOneWidget);
    await tester.tap(find.text('Tick boxes'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('note-editor-format-button')));
    await tester.pumpAndSettle();
    expect(find.text('Heading'), findsOneWidget);
    expect(find.text('Insert hyperlink'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Heading'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('note-editor-more-menu')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Edited '), findsOneWidget);
    expect(find.text('Find in note'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Make a copy'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Collaborator'), findsOneWidget);
    expect(find.text('Labels'), findsOneWidget);
    expect(find.text('Help & feedback'), findsOneWidget);
  });

  testWidgets('formatting toolbar stays above the keyboard inset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(MaterialApp(home: RichNoteEditorScreen()));
    await tester.pumpAndSettle();

    final toolbarRect = tester.getRect(
      find.byKey(const ValueKey('rich-note-formatting-toolbar')),
    );
    expect(toolbarRect.bottom, lessThanOrEqualTo(500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('note color picker uses the approved theme palette', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: RichNoteEditorScreen()));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('note-editor-customize-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Note Colors'), findsOneWidget);
    await tester.tap(find.byTooltip('Pink'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('note-editor-customize-button')),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Pink note color, selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all eight note colors can be selected', (tester) async {
    await tester.pumpWidget(MaterialApp(home: RichNoteEditorScreen()));
    await tester.pumpAndSettle();

    for (final color in [
      'Yellow',
      'Blue',
      'Green',
      'Pink',
      'Purple',
      'Orange',
      'Teal',
      'Lavender',
    ]) {
      await tester.tap(
        find.byKey(const ValueKey('note-editor-customize-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(color));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('note-editor-customize-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('$color note color, selected'),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('note text color saves without changing its background', (
    tester,
  ) async {
    RichNoteDraft? savedDraft;
    final now = DateTime(2026, 10, 1);
    final note = NoteEntry(
      id: 'colored-note',
      notebookId: defaultNotebookId,
      title: 'Colored note',
      content: 'Note body',
      color: NoteCardColor.yellow,
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RichNoteEditorScreen(
          note: note,
          onAutosave: (draft) async {
            savedDraft = draft;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('note-editor-customize-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-text-color-purple')));
    await tester.pump(const Duration(milliseconds: 800));

    expect(savedDraft?.color, NoteCardColor.yellow);
    expect(savedDraft?.textColor, NoteTextColor.purple);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tag colors can be changed and persisted by tag key', (
    tester,
  ) async {
    Map<String, NoteCardColor>? savedTagColors;
    final now = DateTime(2026, 10, 1);
    final note = NoteEntry(
      id: 'tagged-note',
      notebookId: 'notebook',
      title: 'Campaign',
      content: '',
      projectMetadata: const NoteProjectMetadata(tags: ['Campaigns']),
      createdAt: now,
      updatedAt: now,
      color: NoteCardColor.yellow,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RichNoteEditorScreen(
          note: note,
          onTagColorsChanged: (colors) async {
            savedTagColors = colors;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Change Campaigns tag color'));
    await tester.pumpAndSettle();
    expect(find.text('Tag Color'), findsOneWidget);
    await tester.tap(find.byTooltip('Lavender'));
    await tester.pumpAndSettle();

    expect(savedTagColors, containsPair('campaigns', NoteCardColor.lavender));
    expect(find.byTooltip('Change Campaigns tag color'), findsOneWidget);
    await tester.tap(find.byTooltip('Change Campaigns tag color'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Lavender tag color, selected'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor keeps notebook assignment without a dropdown', (
    tester,
  ) async {
    RichNoteDraft? savedDraft;
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
      id: 'work',
      name: 'Work',
      iconType: NotebookIconType.work,
      notes: const [],
      createdAt: now,
      updatedAt: now,
    );
    final note = NoteEntry(
      id: 'note-1',
      notebookId: quickNotes.id,
      title: 'A note',
      content: 'Note content',
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RichNoteEditorScreen(
          note: note,
          notebooks: [quickNotes, work],
          onAutosave: (draft) async {
            savedDraft = draft;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('rich-note-notebook-dropdown')),
      findsNothing,
    );
    expect(find.textContaining('Notebook:'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('rich-note-title-field')),
      'A note edited',
    );
    await tester.pump(const Duration(milliseconds: 800));

    expect(savedDraft?.notebookId, quickNotes.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected text highlight is saved as a rich-text attribute', (
    tester,
  ) async {
    RichNoteDraft? savedDraft;
    await tester.pumpWidget(
      MaterialApp(
        home: RichNoteEditorScreen(
          onAutosave: (draft) async {
            savedDraft = draft;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editor = tester.widget<quill.QuillEditor>(
      find.byKey(const ValueKey('rich-note-content-editor')),
    );
    final controller = editor.controller;
    const noteText = 'Campaign goals';
    controller.document.insert(0, '$noteText\n');
    controller.updateSelection(
      TextSelection(baseOffset: 0, extentOffset: noteText.length),
      quill.ChangeSource.local,
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('note-editor-format-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text colors'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Text highlight Yellow'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();

    final delta = controller.document.toDelta().toJson();
    expect(
      delta.whereType<Map>().any(
        (operation) =>
            operation['attributes'] is Map &&
            (operation['attributes'] as Map).containsKey('background'),
      ),
      isTrue,
    );
    expect(savedDraft?.richContentDelta, contains('background'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple text colors remain readable in both theme modes', (
    tester,
  ) async {
    const words = ['One', 'two', 'three', 'four', 'five', 'six', 'seven'];
    const colorNames = [
      'Yellow',
      'Pink',
      'Purple',
      'Blue',
      'Green',
      'Cyan',
      'Orange',
    ];
    final content = '${words.join(' ')}\n';

    for (final brightness in [Brightness.light, Brightness.dark]) {
      RichNoteDraft? savedDraft;
      final mode = brightness == Brightness.light
          ? ThemeMode.light
          : ThemeMode.dark;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: mode,
          home: RichNoteEditorScreen(
            key: ValueKey('editor-${brightness.name}'),
            onAutosave: (draft) async {
              savedDraft = draft;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final editor = tester.widget<quill.QuillEditor>(
        find.byKey(const ValueKey('rich-note-content-editor')),
      );
      final controller = editor.controller;
      expect(
        Theme.of(
          tester.element(
            find.byKey(const ValueKey('rich-note-content-editor')),
          ),
        ).brightness,
        brightness,
      );
      controller.document.insert(0, content);

      for (var index = 0; index < words.length; index++) {
        final start = content.indexOf(words[index]);
        controller.updateSelection(
          TextSelection(
            baseOffset: start,
            extentOffset: start + words[index].length,
          ),
          quill.ChangeSource.local,
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('note-editor-format-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Text colors'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Text highlight ${colorNames[index]}'));
        await tester.pumpAndSettle();
      }

      for (var index = 0; index < words.length; index++) {
        final start = content.indexOf(words[index]);
        controller.updateSelection(
          TextSelection(
            baseOffset: start,
            extentOffset: start + words[index].length,
          ),
          quill.ChangeSource.local,
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('note-editor-format-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Text colors'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Text color ${colorNames[index]}'));
        await tester.pumpAndSettle();
      }
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();

      final delta = controller.document.toDelta().toJson();
      final highlightColors = <String>{};
      final textColors = <String>{};
      final runs = <String, Map>{};
      for (final operation in delta.whereType<Map>()) {
        final insertedText = operation['insert'];
        final attributes = operation['attributes'];
        if (insertedText is! String || attributes is! Map) {
          continue;
        }
        final background = attributes['background'];
        final foreground = attributes['color'];
        if (background is String) {
          highlightColors.add(background);
        }
        if (foreground is String) {
          textColors.add(foreground);
        }
        for (final word in words) {
          if (insertedText.contains(word)) {
            runs[word] = attributes;
          }
        }
      }

      expect(
        highlightColors,
        hasLength(words.length),
        reason: 'Serialized delta: $delta',
      );
      expect(textColors, hasLength(words.length));
      for (final word in words) {
        final attributes = runs[word]!;
        final foreground = _colorFromHex(attributes['color']! as String);
        final background = _colorFromHex(attributes['background']! as String);
        expect(
          _contrastRatio(foreground, background),
          greaterThanOrEqualTo(4.5),
        );
      }
      expect(savedDraft?.richContentDelta, contains('background'));
      expect(savedDraft?.richContentDelta, contains('color'));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('editor and reminder sheet render across theme modes and sizes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
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
          home: RichNoteEditorScreen(),
        ),
      );
      await tester.pumpAndSettle();
      final expectedBrightness = mode == ThemeMode.system
          ? systemBrightness
          : mode == ThemeMode.dark
          ? Brightness.dark
          : Brightness.light;
      expect(
        Theme.of(
          tester.element(
            find.byKey(const ValueKey('rich-note-content-editor')),
          ),
        ).brightness,
        expectedBrightness,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey('note-editor-reminder-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Set Reminder'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.text('Set Reminder'))).brightness,
        expectedBrightness,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('note-reminder-done-button')),
      );
      await tester.tap(find.byKey(const ValueKey('note-reminder-done-button')));
      await tester.pumpAndSettle();
    }
  });
}

Color _colorFromHex(String hex) {
  final value = hex.replaceFirst('#', '');
  return Color(0xFF000000 | int.parse(value, radix: 16));
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
