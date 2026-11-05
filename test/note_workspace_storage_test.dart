import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_smarana/features/notes/models/note_workspace_models.dart';
import 'package:app_smarana/features/notes/services/note_attachment_storage.dart';
import 'package:app_smarana/features/notes/services/note_workspace_storage.dart';
import 'package:app_smarana/features/notes/theme/note_card_colors.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late NoteWorkspaceStorage storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = NoteWorkspaceStorage();
  });

  test('persists notebook, note, rich content, and timestamps', () async {
    final createdAt = DateTime(2026, 9, 1, 10);
    final updatedAt = DateTime(2026, 9, 30, 14, 25);
    final notebook = Notebook(
      id: 'notebook-1',
      name: 'Work',
      description: 'Project planning and team notes.',
      iconType: NotebookIconType.work,
      icon: NotebookIcon.science,
      colorValue: 0xFFE06E91,
      notes: [
        NoteEntry(
          id: 'note-1',
          notebookId: 'notebook-1',
          title: 'Review',
          content: 'Review agenda',
          richContentDelta: '[{"insert":"Review agenda\\n"}]',
          attachments: [
            NoteAttachment(
              id: 'attachment-1',
              name: 'agenda.pdf',
              path: '/local/agenda.pdf',
              type: NoteAttachmentType.file,
              addedAt: updatedAt,
            ),
          ],
          projectMetadata: NoteProjectMetadata(
            owner: 'Ramya',
            tags: ['Launch', 'Q4'],
            startDate: DateTime(2026, 9, 1),
            endDate: DateTime(2026, 10, 1),
            priority: NoteProjectPriority.high,
            status: NoteProjectStatus.inProgress,
            relatedCalendarEventId: 'event-42',
          ),
          isPinned: true,
          color: NoteCardColor.pink,
          textColor: NoteTextColor.purple,
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
      ],
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    await storage.saveWorkspace([notebook]);
    final loaded = await storage.loadWorkspace();
    expect(loaded.any((item) => item.id == defaultNotebookId), isTrue);
    final restored = loaded.singleWhere((item) => item.id == notebook.id);

    expect(restored.name, notebook.name);
    expect(restored.description, notebook.description);
    expect(restored.icon, notebook.icon);
    expect(restored.colorValue, notebook.colorValue);
    expect(restored.createdAt, createdAt);
    expect(restored.updatedAt, updatedAt);
    expect(restored.notes.single.title, 'Review');
    expect(restored.notes.single.content, 'Review agenda');
    expect(
      restored.notes.single.richContentDelta,
      notebook.notes.single.richContentDelta,
    );
    expect(restored.notes.single.attachments.single.name, 'agenda.pdf');
    expect(
      restored.notes.single.attachments.single.type,
      NoteAttachmentType.file,
    );
    expect(restored.notes.single.projectMetadata?.owner, 'Ramya');
    expect(restored.notes.single.projectMetadata?.tags, ['Launch', 'Q4']);
    expect(
      restored.notes.single.projectMetadata?.priority,
      NoteProjectPriority.high,
    );
    expect(
      restored.notes.single.projectMetadata?.status,
      NoteProjectStatus.inProgress,
    );
    expect(
      restored.notes.single.projectMetadata?.relatedCalendarEventId,
      'event-42',
    );
    expect(restored.notes.single.isPinned, isTrue);
    expect(restored.notes.single.color, NoteCardColor.pink);
    expect(restored.notes.single.textColor, NoteTextColor.purple);
    expect(restored.notes.single.content, 'Review agenda');
    expect(restored.notes.single.createdAt, createdAt);
    expect(restored.notes.single.updatedAt, updatedAt);
  });

  test(
    'preserves corrupted workspace data and refuses to overwrite it',
    () async {
      final preferences = await SharedPreferences.getInstance();
      const raw = '{invalid';
      await preferences.setString('smarana_note_workspace_v1', raw);

      await expectLater(storage.saveWorkspace([]), throwsFormatException);
      await expectLater(storage.loadWorkspace(), throwsFormatException);
      expect(preferences.getString('smarana_note_workspace_v1'), raw);
    },
  );

  test('does not overwrite a workspace from a newer schema version', () async {
    final preferences = await SharedPreferences.getInstance();
    const raw = '{"version":999,"notebooks":[{"future":"data"}]}';
    await preferences.setString('smarana_note_workspace_v1', raw);

    await expectLater(storage.saveWorkspace([]), throwsFormatException);
    await expectLater(storage.loadWorkspace(), throwsFormatException);
    expect(preferences.getString('smarana_note_workspace_v1'), raw);
  });

  test('preserves workspace data with malformed nested attachments', () async {
    final preferences = await SharedPreferences.getInstance();
    final now = DateTime(2026, 10, 1);
    final note = NoteEntry(
      id: 'note-with-attachment',
      notebookId: defaultNotebookId,
      title: 'Attachment',
      content: '',
      createdAt: now,
      updatedAt: now,
    ).toJson();
    note['attachments'] = ['unreadable attachment'];
    final notebook = Notebook(
      id: defaultNotebookId,
      name: defaultNotebookName,
      iconType: NotebookIconType.general,
      notes: const [],
      createdAt: now,
      updatedAt: now,
    ).toJson();
    notebook['notes'] = [note];
    final raw = jsonEncode({
      'version': 4,
      'notebooks': [notebook],
      'tagColors': <String, String>{},
    });
    await preferences.setString('smarana_note_workspace_v1', raw);

    await expectLater(storage.loadWorkspace(), throwsFormatException);
    await expectLater(storage.saveWorkspace([]), throwsFormatException);
    expect(preferences.getString('smarana_note_workspace_v1'), raw);
  });

  test('preserves workspace data with malformed attachment fields', () async {
    final preferences = await SharedPreferences.getInstance();
    final now = DateTime(2026, 10, 1);
    final note = NoteEntry(
      id: 'note-with-attachment',
      notebookId: defaultNotebookId,
      title: 'Attachment',
      content: '',
      createdAt: now,
      updatedAt: now,
    ).toJson();
    note['attachments'] = [
      {
        'id': 7,
        'name': 'agenda.pdf',
        'path': '/local/agenda.pdf',
        'type': 'unsupported',
        'addedAt': now.toIso8601String(),
      },
    ];
    final notebook = Notebook(
      id: defaultNotebookId,
      name: defaultNotebookName,
      iconType: NotebookIconType.general,
      notes: const [],
      createdAt: now,
      updatedAt: now,
    ).toJson();
    notebook['notes'] = [note];
    final raw = jsonEncode({
      'version': 4,
      'notebooks': [notebook],
      'tagColors': <String, String>{},
    });
    await preferences.setString('smarana_note_workspace_v1', raw);

    await expectLater(storage.loadWorkspace(), throwsFormatException);
    await expectLater(storage.saveWorkspace([]), throwsFormatException);
    expect(preferences.getString('smarana_note_workspace_v1'), raw);
  });

  test('preserves malformed saved tag colors', () async {
    final preferences = await SharedPreferences.getInstance();
    final now = DateTime(2026, 10, 1);
    final notebook = Notebook(
      id: defaultNotebookId,
      name: defaultNotebookName,
      iconType: NotebookIconType.general,
      notes: const [],
      createdAt: now,
      updatedAt: now,
    );
    final raw = jsonEncode({
      'version': 4,
      'notebooks': [notebook.toJson()],
      'tagColors': {'work': 42},
    });
    await preferences.setString('smarana_note_workspace_v1', raw);

    await expectLater(storage.loadWorkspace(), throwsFormatException);
    await expectLater(storage.saveWorkspace([notebook]), throwsFormatException);
    expect(preferences.getString('smarana_note_workspace_v1'), raw);
  });

  test('blocks saves after a migration write fails', () async {
    final preferences = await SharedPreferences.getInstance();
    const raw =
        '{"version":1,"notebooks":[{"id":"legacy","name":"Legacy","notes":[]}]}';
    await preferences.setString('smarana_note_workspace_v1', raw);
    var writes = 0;
    final storage = NoteWorkspaceStorage(
      saveString: (key, value) async {
        writes++;
        if (writes == 1) {
          return false;
        }
        return preferences.setString(key, value);
      },
    );

    await expectLater(storage.loadWorkspace(), throwsA(isA<Exception>()));
    await expectLater(
      storage.saveWorkspace([
        Notebook(
          id: defaultNotebookId,
          name: defaultNotebookName,
          iconType: NotebookIconType.general,
          notes: const [],
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 1),
        ),
      ]),
      throwsFormatException,
    );
    expect(preferences.getString('smarana_note_workspace_v1'), raw);

    final recovered = await storage.loadWorkspace();
    expect(
      recovered.any((notebook) => notebook.id == defaultNotebookId),
      isTrue,
    );
    expect(
      (jsonDecode(preferences.getString('smarana_note_workspace_v1')!)
          as Map)['version'],
      4,
    );
    await storage.saveWorkspace(recovered);
  });

  test(
    'assigns and persists colors for existing uncolored notes once',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'smarana_note_workspace_v1',
        jsonEncode({
          'version': 1,
          'notebooks': [
            {
              'id': 'notebook-legacy',
              'name': 'Legacy',
              'sections': [
                {'id': 'section-legacy', 'name': 'General'},
              ],
              'notes': [
                {
                  'id': 'note-legacy-1',
                  'notebookId': 'notebook-legacy',
                  'sectionId': 'section-legacy',
                  'title': 'First',
                  'content': 'Legacy note content',
                  'projectMetadata': {
                    'tags': ['Campaigns'],
                  },
                },
                {
                  'id': 'note-legacy-2',
                  'notebookId': 'notebook-legacy',
                  'sectionId': 'section-legacy',
                  'title': 'Second',
                },
              ],
            },
            {
              'id': 'notebook-legacy-2',
              'name': 'Existing',
              'sections': [],
              'notes': [],
            },
          ],
        }),
      );

      final firstLoad = await storage.loadWorkspace();
      expect(
        firstLoad.map((notebook) => notebook.colorValue).toSet().length,
        3,
      );
      final legacyNotebook = firstLoad.singleWhere(
        (notebook) => notebook.id == 'notebook-legacy',
      );
      expect(legacyNotebook.description, isEmpty);
      expect(legacyNotebook.icon, isNull);
      expect(legacyNotebook.notes.map((note) => note.id), [
        'note-legacy-1',
        'note-legacy-2',
      ]);
      expect(legacyNotebook.notes.first.notebookId, 'notebook-legacy');
      expect(legacyNotebook.notes.first.content, 'Legacy note content');
      final migratedColors = legacyNotebook.notes
          .map((note) => note.color)
          .toList();
      expect(migratedColors, [NoteCardColor.yellow, NoteCardColor.blue]);

      final persisted = jsonDecode(
        preferences.getString('smarana_note_workspace_v1')!,
      ) as Map;
      expect(persisted['version'], 4);
      final persistedNotebooks = persisted['notebooks'] as List;
      final persistedLegacy = persistedNotebooks.singleWhere(
        (notebook) => notebook['id'] == 'notebook-legacy',
      ) as Map;
      expect(persistedLegacy['description'], isEmpty);
      expect(persistedLegacy['icon'], isNull);
      expect(persistedLegacy['colorValue'], isA<int>());
      expect(persistedLegacy.containsKey('sections'), isFalse);
      expect(
        (persistedLegacy['notes'] as List)
            .map((note) => note['color'])
            .toList(),
        ['yellow', 'blue'],
      );
      expect(
        (persistedLegacy['notes'] as List).every(
          (note) => !(note as Map).containsKey('sectionId'),
        ),
        isTrue,
      );
      expect(
        (await storage.loadWorkspace())
            .singleWhere((notebook) => notebook.id == 'notebook-legacy')
            .notes
            .map((note) => note.color)
            .toList(),
        migratedColors,
      );
      expect(await storage.loadTagColors(), {
        'campaigns': NoteCardColor.yellow,
      });
    },
  );

  test('persists shared tag colors in the Notes workspace', () async {
    final now = DateTime(2026, 10, 1);
    final notebook = Notebook(
      id: 'tag-notebook',
      name: 'Work',
      iconType: NotebookIconType.work,
      notes: const [],
      createdAt: now,
      updatedAt: now,
    );

    await storage.saveWorkspace(
      [notebook],
      tagColors: {'campaigns': NoteCardColor.lavender},
    );

    expect(await storage.loadTagColors(), {
      'campaigns': NoteCardColor.lavender,
    });
    expect(
      (await storage.loadWorkspace())
          .singleWhere((item) => item.id == defaultNotebookId)
          .name,
      defaultNotebookName,
    );
  });

  test(
    'normalizes an existing Quick Notes notebook without losing its notes',
    () async {
      final now = DateTime(2026, 10, 1);
      final legacyQuickNotes = Notebook(
        id: 'old-quick-notes',
        name: 'quick notes',
        iconType: NotebookIconType.general,
        notes: [
          NoteEntry(
            id: 'quick-note',
            notebookId: 'old-quick-notes',
            title: 'Keep this note',
            content: 'Existing content',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await storage.saveWorkspace([legacyQuickNotes]);
      final notebooks = await storage.loadWorkspace();
      final quickNotes = notebooks.singleWhere(isDefaultNotebook);

      expect(quickNotes.name, defaultNotebookName);
      expect(quickNotes.notes.single.title, 'Keep this note');
      expect(quickNotes.notes.single.content, 'Existing content');
      expect(quickNotes.notes.single.notebookId, defaultNotebookId);
    },
  );

  test('assigns new note colors with a balanced palette', () {
    final notes = <NoteEntry>[];
    final selected = <NoteCardColor>[];
    final now = DateTime(2026, 10, 1);
    for (var index = 0; index < selectableNoteCardColors.length; index++) {
      final color = nextBalancedNoteColor(notes);
      selected.add(color);
      notes.add(
        NoteEntry(
          id: 'note-$index',
          notebookId: 'notebook',
          title: 'Note $index',
          content: '',
          createdAt: now,
          updatedAt: now,
          color: color,
        ),
      );
    }

    expect(selected, selectableNoteCardColors);
  });

  test(
    'copies attachments locally, handles missing files, and removes files',
    () async {
      final root = await Directory.systemTemp.createTemp('smarana-notes-');
      addTearDown(() => root.delete(recursive: true));
      final attachmentStorage = NoteAttachmentStorage(rootDirectory: root);
      final attachment = await attachmentStorage.importFile(
        file: PlatformFile(
          name: 'photo.png',
          size: 3,
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        noteId: 'note-1',
        type: NoteAttachmentType.image,
      );

      expect(await attachmentStorage.exists(attachment), isTrue);
      expect(await File(attachment.path).readAsBytes(), [1, 2, 3]);
      expect(
        await attachmentStorage.open(
          attachment.copyWith(path: '${attachment.path}.missing'),
        ),
        isFalse,
      );

      await attachmentStorage.remove(attachment);
      expect(await attachmentStorage.exists(attachment), isFalse);
      await attachmentStorage.remove(attachment);
    },
  );
}
