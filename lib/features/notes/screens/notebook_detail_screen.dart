import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/app_design_tokens.dart';
import '../../reminders/services/reminder_storage.dart';
import '../models/note_workspace_models.dart';
import '../models/rich_note_draft.dart';
import '../services/note_attachment_storage.dart';
import '../theme/note_card_colors.dart';
import '../theme/notebook_colors.dart';
import '../widgets/note_tag_chip.dart';
import '../../../widgets/app_navigation_drawer.dart';
import 'rich_note_editor_screen.dart';

enum NotebookViewMode { notes, list, kanban }

class NotebookDetailResult {
  const NotebookDetailResult({this.updatedNotebook, this.isDeleted = false});

  final Notebook? updatedNotebook;
  final bool isDeleted;
}

class NotebookDetailScreen extends StatefulWidget {
  const NotebookDetailScreen({
    super.key,
    required this.notebook,
    this.notebooks = const [],
    this.onNotebookChanged,
    this.onNoteChanged,
    this.onNoteDeleted,
    this.reminderStorage,
    this.initialNoteId,
    this.tagColors = const {},
    this.onTagColorsChanged,
    this.navigationDrawer,
  });

  final Notebook notebook;
  final List<Notebook> notebooks;
  final Future<void> Function(Notebook notebook)? onNotebookChanged;
  final Future<void> Function(NoteEntry note)? onNoteChanged;
  final Future<void> Function(String noteId)? onNoteDeleted;
  final ReminderStorage? reminderStorage;
  final String? initialNoteId;
  final Map<String, NoteCardColor> tagColors;
  final Future<void> Function(Map<String, NoteCardColor> tagColors)?
  onTagColorsChanged;
  final Widget? navigationDrawer;

  @override
  State<NotebookDetailScreen> createState() => _NotebookDetailScreenState();
}

class _NotebookDetailScreenState extends State<NotebookDetailScreen> {
  late Notebook _notebook;
  late final ReminderStorage _reminderStorage;
  late final NoteAttachmentStorage _attachmentStorage;
  late Map<String, NoteCardColor> _tagColors;
  NotebookViewMode _viewMode = NotebookViewMode.notes;

  @override
  void initState() {
    super.initState();
    _notebook = widget.notebook;
    _reminderStorage = widget.reminderStorage ?? ReminderStorage();
    _attachmentStorage = NoteAttachmentStorage();
    _tagColors = Map<String, NoteCardColor>.of(widget.tagColors);
    if (widget.initialNoteId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final matches = _notebook.notes.where(
          (note) => note.id == widget.initialNoteId,
        );
        if (matches.isNotEmpty) {
          unawaited(_editNote(matches.first));
        }
      });
    }
  }

  List<NoteEntry> get _notes {
    final notes = List<NoteEntry>.of(_notebook.notes);
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return notes;
  }

  Future<void> _createNote() async {
    final now = DateTime.now();
    final note = NoteEntry(
      id: _id('note'),
      notebookId: _notebook.id,
      title: '',
      content: '',
      createdAt: now,
      updatedAt: now,
      color: nextBalancedNoteColor(_notebook.notes),
    );

    var wasInserted = false;
    final draft = await Navigator.of(context).push<RichNoteDraft>(
      MaterialPageRoute<RichNoteDraft>(
        builder: (_) => RichNoteEditorScreen(
          note: note,
          notebooks: widget.notebooks.isEmpty ? [_notebook] : widget.notebooks,
          focusOnOpen: true,
          tagColors: _tagColors,
          navigationDrawer: widget.navigationDrawer,
          onTagColorsChanged: _updateTagColors,
          reminderStorage: _reminderStorage,
          onDuplicate: _duplicateDraft,
          onDelete: (draft) async {
            if (draft.reminderId != null) {
              await _reminderStorage.deleteReminder(draft.reminderId!);
            }
            if (wasInserted) {
              await _deleteNoteFromWorkspace(note.id);
            }
          },
          onPinChanged: (snapshot) async {
            await _saveNote(_noteFromDraft(base: note, draft: snapshot));
            wasInserted = true;
          },
          onArchiveChanged: (snapshot) async {
            await _saveNote(_noteFromDraft(base: note, draft: snapshot));
            wasInserted = true;
          },
          onAutosave: (snapshot) async {
            if (!_hasMeaningfulContent(snapshot) || !mounted) {
              return;
            }
            await _saveNote(_noteFromDraft(base: note, draft: snapshot));
            wasInserted = true;
          },
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    if (draft == null || !_hasMeaningfulContent(draft)) {
      if (wasInserted) {
        await _deleteNoteFromWorkspace(note.id);
      }
      final orphanedReminderId = draft?.reminderId;
      if (orphanedReminderId != null) {
        await _reminderStorage.deleteReminder(orphanedReminderId);
      }
      return;
    }

    final updated = _noteFromDraft(base: note, draft: draft);
    await _saveNote(updated);
  }

  Future<void> _editNote(NoteEntry note) async {
    final draft = await Navigator.of(context).push<RichNoteDraft>(
      MaterialPageRoute<RichNoteDraft>(
        builder: (_) => RichNoteEditorScreen(
          note: note,
          notebooks: widget.notebooks.isEmpty ? [_notebook] : widget.notebooks,
          tagColors: _tagColors,
          navigationDrawer: widget.navigationDrawer,
          onTagColorsChanged: _updateTagColors,
          reminderStorage: _reminderStorage,
          onDuplicate: _duplicateDraft,
          onDelete: (draft) async {
            if (draft.reminderId != null) {
              await _reminderStorage.deleteReminder(draft.reminderId!);
            }
            await _deleteNoteFromWorkspace(note.id);
          },
          onPinChanged: (snapshot) async {
            await _saveNote(_noteFromDraft(base: note, draft: snapshot));
          },
          onArchiveChanged: (snapshot) async {
            await _saveNote(_noteFromDraft(base: note, draft: snapshot));
          },
          onAutosave: (snapshot) async {
            if (!mounted) {
              return;
            }
            await _saveNote(_noteFromDraft(base: note, draft: snapshot));
          },
        ),
      ),
    );

    if (!mounted || draft == null) {
      return;
    }

    final updated = _noteFromDraft(base: note, draft: draft);
    await _saveNote(updated);
  }

  Future<void> _duplicateDraft(RichNoteDraft draft) async {
    final id = _id('note');
    final attachments = await _attachmentStorage.duplicateAttachments(
      attachments: draft.attachments,
      noteId: id,
    );
    final now = DateTime.now();
    final title = draft.title.trim().isEmpty ? 'Untitled' : draft.title.trim();
    final duplicate = NoteEntry(
      id: id,
      notebookId: draft.notebookId,
      title: '$title copy',
      content: draft.plainContent,
      richContentDelta: draft.richContentDelta,
      attachments: attachments,
      projectMetadata: draft.projectMetadata,
      createdAt: now,
      updatedAt: now,
      color: draft.color,
      textColor: draft.textColor,
    );
    await _saveNote(duplicate);
  }

  Future<void> _publishNotebook(Notebook updated) async {
    setState(() {
      _notebook = updated;
    });
    await widget.onNotebookChanged?.call(updated);
  }

  Future<void> _saveNote(NoteEntry note) async {
    final notes = _notebook.notes
        .where((existing) => existing.id != note.id)
        .toList();
    if (note.notebookId == _notebook.id) {
      notes.add(note);
    }
    final updated = _notebook.copyWith(notes: notes, updatedAt: note.updatedAt);
    setState(() {
      _notebook = updated;
    });
    final onNoteChanged = widget.onNoteChanged;
    if (onNoteChanged != null) {
      await onNoteChanged(note);
    } else {
      await widget.onNotebookChanged?.call(updated);
    }
  }

  Future<void> _deleteNoteFromWorkspace(String noteId) async {
    final updated = _notebook.copyWith(
      notes: _notebook.notes
          .where((existing) => existing.id != noteId)
          .toList(),
      updatedAt: DateTime.now(),
    );
    setState(() {
      _notebook = updated;
    });
    final onNoteDeleted = widget.onNoteDeleted;
    if (onNoteDeleted != null) {
      await onNoteDeleted(noteId);
    } else {
      await widget.onNotebookChanged?.call(updated);
    }
  }

  Future<void> _updateTagColors(Map<String, NoteCardColor> tagColors) async {
    setState(() {
      _tagColors = Map<String, NoteCardColor>.of(tagColors);
    });
    await widget.onTagColorsChanged?.call(_tagColors);
  }

  Future<void> _changeTagColor(String tag, NoteCardColor color) async {
    final updated = Map<String, NoteCardColor>.of(_tagColors)
      ..[tag.trim().toLowerCase()] = color;
    await _updateTagColors(updated);
  }

  Future<void> _pickTagColor(String tag) async {
    final currentColor = _tagColor(tag, 0);
    final selectedColor = await showNoteTagColorPicker(
      context,
      current: currentColor,
    );
    if (selectedColor != null && mounted) {
      await _changeTagColor(tag, selectedColor);
    }
  }

  NoteEntry _noteFromDraft({
    required NoteEntry base,
    required RichNoteDraft draft,
  }) {
    return base.copyWith(
      notebookId: draft.notebookId,
      title: draft.title,
      content: draft.plainContent,
      richContentDelta: draft.richContentDelta,
      attachments: draft.attachments,
      projectMetadata: draft.projectMetadata,
      clearProjectMetadata: draft.projectMetadata == null,
      updatedAt: draft.updatedAt,
      reminderId: draft.reminderId,
      clearReminderId: draft.reminderId == null,
      color: draft.color,
      textColor: draft.textColor,
      isPinned: draft.isPinned,
      isArchived: draft.isArchived,
    );
  }

  Future<void> _moveNoteToStatus(
    NoteEntry note,
    NoteProjectStatus status,
  ) async {
    final now = DateTime.now();
    final currentMetadata = note.projectMetadata;
    final updatedMetadata = (currentMetadata ?? const NoteProjectMetadata())
        .copyWith(status: status);
    final updatedNote = note.copyWith(
      projectMetadata: updatedMetadata,
      updatedAt: now,
    );
    await _publishNotebook(
      _notebook.copyWith(
        notes: _upsertNote(_notebook.notes, updatedNote),
        updatedAt: now,
      ),
    );
  }

  List<NoteEntry> _upsertNote(List<NoteEntry> notes, NoteEntry note) {
    final next = List<NoteEntry>.of(notes);
    final index = next.indexWhere((entry) => entry.id == note.id);
    if (index == -1) {
      next.add(note);
    } else {
      next[index] = note;
    }
    return next;
  }

  bool _hasMeaningfulContent(RichNoteDraft draft) {
    return draft.title.trim().isNotEmpty ||
        draft.plainContent.trim().isNotEmpty ||
        draft.attachments.isNotEmpty ||
        draft.isPinned ||
        draft.isArchived;
  }

  Future<void> _deleteNote(NoteEntry note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('Delete note?'),
        content: Text(
          'Delete "${note.title.isEmpty ? 'Untitled note' : note.title}"? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final reminderId = note.reminderId;
    if (reminderId != null) {
      await _reminderStorage.deleteReminder(reminderId);
    }

    await _publishNotebook(
      _notebook.copyWith(
        notes: _notebook.notes.where((item) => item.id != note.id).toList(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  String _id(String prefix) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final notebookAccent = notebookAccentColor(theme, _notebook.colorValue);

    return Scaffold(
      drawer: widget.navigationDrawer,
      appBar: AppBar(
        leadingWidth: widget.navigationDrawer == null ? null : 104,
        leading: widget.navigationDrawer == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppNavigationMenuButton(),
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ],
              ),
        title: Row(
          children: [
            Icon(
              notebookIconData(_notebook.icon, _notebook.iconType),
              color: notebookAccent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _notebook.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: notebookAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
      body: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_notebook.noteCount} ${_notebook.noteCount == 1 ? 'note' : 'notes'}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('notebook-new-note-button'),
                        onPressed: _createNote,
                        icon: const Icon(Icons.note_add_outlined),
                        label: const Text('New Note'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<NotebookViewMode>(
                      key: const ValueKey('notebook-view-segmented-button'),
                      segments: const [
                        ButtonSegment<NotebookViewMode>(
                          value: NotebookViewMode.notes,
                          icon: Icon(Icons.notes_outlined),
                          label: Text('Document'),
                        ),
                        ButtonSegment<NotebookViewMode>(
                          value: NotebookViewMode.list,
                          icon: Icon(Icons.view_list_outlined),
                          label: Text('List'),
                        ),
                        ButtonSegment<NotebookViewMode>(
                          value: NotebookViewMode.kanban,
                          icon: Icon(Icons.view_kanban_outlined),
                          label: Text('Kanban'),
                        ),
                      ],
                      selected: {_viewMode},
                      onSelectionChanged: (selection) {
                        if (selection.isEmpty) {
                          return;
                        }
                        setState(() {
                          _viewMode = selection.first;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: switch (_viewMode) {
                NotebookViewMode.notes => _buildDocumentView(
                  theme,
                  colorScheme,
                ),
                NotebookViewMode.list => _buildListView(theme, colorScheme),
                NotebookViewMode.kanban => _buildKanbanView(theme, colorScheme),
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('notebook-save-and-close'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.compactCard),
        ),
        onPressed: () {
          Navigator.of(context)
              .pop(NotebookDetailResult(updatedNotebook: _notebook));
        },
        icon: const Icon(Icons.check),
        label: const Text('Done'),
      ),
    );
  }

  Widget _buildDocumentView(ThemeData theme, ColorScheme colorScheme) {
    final notes = _notes;
    if (notes.isEmpty) {
      return Center(
        child: Text(
          'No notes in this notebook yet',
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemBuilder: (context, index) {
        final note = notes[index];
        final metadata = note.projectMetadata;
        final noteForeground = noteCardForegroundColor(
          theme,
          note.color,
          note.textColor,
        );
        return Card(
          color: noteCardSurfaceColor(theme, note.color),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: ListTile(
            onTap: () => _editNote(note),
            leading: note.reminderId != null
                ? Icon(
                    Icons.notifications_active_outlined,
                    color: noteForeground,
                  )
                : null,
            title: Text(
              note.title.isEmpty ? 'Untitled note' : note.title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: noteForeground,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: noteForeground,
                  ),
                ),
                if (metadata != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var index = 0; index < metadata.tags.length; index++)
                        NoteTagChip(
                          label: metadata.tags[index],
                          color: _tagColor(metadata.tags[index], index),
                          onColorChange: () =>
                              _pickTagColor(metadata.tags[index]),
                        ),
                      _statusChip(metadata.status),
                      if (metadata.priority != null)
                        Chip(
                          label: Text(_priorityLabel(metadata.priority!)),
                          visualDensity: VisualDensity.compact,
                        ),
                      if ((metadata.owner ?? '').trim().isNotEmpty)
                        Chip(
                          label: Text('Owner: ${metadata.owner!.trim()}'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ],
            ),
            trailing: IconButton(
              key: ValueKey('delete-note-${note.id}'),
              tooltip: 'Delete note',
              icon: Icon(Icons.delete_outline, color: noteForeground),
              onPressed: () => _deleteNote(note),
            ),
          ),
        );
      },
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemCount: notes.length,
    );
  }

  Widget _buildListView(ThemeData theme, ColorScheme colorScheme) {
    final notes = _notes;
    if (notes.isEmpty) {
      return Center(
        child: Text(
          'No notes in this notebook yet',
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemBuilder: (context, index) {
        final note = notes[index];
        final metadata = note.projectMetadata;
        final status = metadata?.status ?? NoteProjectStatus.toDo;
        final noteForeground = noteCardForegroundColor(
          theme,
          note.color,
          note.textColor,
        );
        return Card(
          color: noteCardSurfaceColor(theme, note.color),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: ListTile(
            key: ValueKey('list-note-${note.id}'),
            onTap: () => _editNote(note),
            title: Text(
              note.title.isEmpty ? 'Untitled note' : note.title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: noteForeground,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metadata?.owner == null
                      ? _statusLabel(status)
                      : 'Owner: ${metadata!.owner} · ${_statusLabel(status)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: noteForeground,
                  ),
                ),
                if (metadata?.tags.isNotEmpty ?? false) ...[
                  const SizedBox(height: 4),
                  _buildNoteTags(metadata!.tags),
                ],
              ],
            ),
            leading: _statusChip(status),
            trailing: PopupMenuButton<NoteProjectStatus>(
              tooltip: 'Move status',
              onSelected: (value) {
                _moveNoteToStatus(note, value);
              },
              itemBuilder: (context) => const [
                PopupMenuItem<NoteProjectStatus>(
                  value: NoteProjectStatus.toDo,
                  child: Text('Move to To Do'),
                ),
                PopupMenuItem<NoteProjectStatus>(
                  value: NoteProjectStatus.inProgress,
                  child: Text('Move to In Progress'),
                ),
                PopupMenuItem<NoteProjectStatus>(
                  value: NoteProjectStatus.done,
                  child: Text('Move to Done'),
                ),
              ],
            ),
          ),
        );
      },
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemCount: notes.length,
    );
  }

  Widget _buildKanbanView(ThemeData theme, ColorScheme colorScheme) {
    final notes = _notes;
    if (notes.isEmpty) {
      return Center(
        child: Text(
          'No notes in this notebook yet',
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final grouped = <NoteProjectStatus, List<NoteEntry>>{
      NoteProjectStatus.toDo: [],
      NoteProjectStatus.inProgress: [],
      NoteProjectStatus.done: [],
    };

    for (final note in notes) {
      final status = note.projectMetadata?.status ?? NoteProjectStatus.toDo;
      grouped[status]!.add(note);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final columns = NoteProjectStatus.values
            .map(
              (status) => _buildKanbanColumn(
                status: status,
                notes: grouped[status]!,
                theme: theme,
                colorScheme: colorScheme,
              ),
            )
            .toList();

        if (compact) {
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            itemBuilder: (context, index) => columns[index],
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemCount: columns.length,
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < columns.length; i++) ...[
              Expanded(child: columns[i]),
              if (i != columns.length - 1) const SizedBox(width: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _buildKanbanColumn({
    required NoteProjectStatus status,
    required List<NoteEntry> notes,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    return DragTarget<NoteEntry>(
      onWillAcceptWithDetails: (details) {
        return details.data.projectMetadata?.status != status;
      },
      onAcceptWithDetails: (details) {
        _moveNoteToStatus(details.data, status);
      },
      builder: (context, candidateData, rejectedData) {
        final hasCandidate = candidateData.isNotEmpty;
        return Container(
          key: ValueKey('kanban-column-${status.name}'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: hasCandidate
                ? colorScheme.primaryContainer.withValues(alpha: 0.45)
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${_statusLabel(status)} (${notes.length})',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              if (notes.isEmpty)
                Text(
                  'Drop notes here',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              else
                ...notes.map((note) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: LongPressDraggable<NoteEntry>(
                      data: note,
                      feedback: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: _kanbanCard(
                            note: note,
                            theme: theme,
                            colorScheme: colorScheme,
                          ),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.4,
                        child: _kanbanCard(
                          note: note,
                          theme: theme,
                          colorScheme: colorScheme,
                        ),
                      ),
                      child: _kanbanCard(
                        note: note,
                        theme: theme,
                        colorScheme: colorScheme,
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _kanbanCard({
    required NoteEntry note,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final metadata = note.projectMetadata;
    final noteForeground = noteCardForegroundColor(
      theme,
      note.color,
      note.textColor,
    );
    return Card(
      color: noteCardSurfaceColor(theme, note.color),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: ListTile(
        dense: true,
        onTap: () => _editNote(note),
        title: Text(
          note.title.isEmpty ? 'Untitled note' : note.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(color: noteForeground),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              metadata?.owner == null
                  ? note.preview
                  : 'Owner: ${metadata!.owner}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: noteForeground),
            ),
            if (metadata?.tags.isNotEmpty ?? false) ...[
              const SizedBox(height: 4),
              _buildNoteTags(metadata!.tags),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNoteTags(List<String> tags) {
    return Wrap(
      spacing: 5,
      runSpacing: 3,
      children: [
        for (var index = 0; index < tags.length; index++)
          NoteTagChip(
            label: tags[index],
            color: _tagColor(tags[index], index),
            onColorChange: () => _pickTagColor(tags[index]),
          ),
      ],
    );
  }

  NoteCardColor _tagColor(String tag, int index) {
    return _tagColors[tag.trim().toLowerCase()] ??
        selectableNoteCardColors[index % selectableNoteCardColors.length];
  }

  Widget _statusChip(NoteProjectStatus status) {
    return Chip(
      label: Text(_statusLabel(status)),
      visualDensity: VisualDensity.compact,
    );
  }

  String _statusLabel(NoteProjectStatus status) {
    return switch (status) {
      NoteProjectStatus.toDo => 'To Do',
      NoteProjectStatus.inProgress => 'In Progress',
      NoteProjectStatus.done => 'Done',
    };
  }

  String _priorityLabel(NoteProjectPriority priority) {
    return switch (priority) {
      NoteProjectPriority.low => 'Low',
      NoteProjectPriority.medium => 'Medium',
      NoteProjectPriority.high => 'High',
    };
  }
}
