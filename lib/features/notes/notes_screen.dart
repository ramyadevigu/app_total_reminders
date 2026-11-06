import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../reminders/models/reminder.dart';
import '../reminders/services/reminder_storage.dart';
import '../../theme/app_design_tokens.dart';
import 'models/note_workspace_models.dart';
import 'models/rich_note_draft.dart';
import 'screens/rich_note_editor_screen.dart';
import 'screens/notebook_detail_screen.dart';
import 'services/note_attachment_storage.dart';
import 'theme/note_card_colors.dart';
import 'theme/notebook_colors.dart';
import 'services/note_workspace_storage.dart';
import 'widgets/notes_home_quick_create_menu.dart';
import 'widgets/recent_note_card.dart';
import '../../widgets/app_navigation_drawer.dart';

enum _NotesDestination { notes, archive, deleted }

enum _NotesSortOrder { recommended, recentlyUpdated, title }

class NotesScreen extends StatefulWidget {
  const NotesScreen({
    super.key,
    this.appMenu,
    this.navigationDrawer,
    this.onBackToSmarana,
    this.onNavigateToTab,
    this.onWorkspaceChanged,
    this.onOpenSettings,
    this.onOpenHelp,
    this.initialNotebooks,
    this.workspaceStorage,
    this.useInternalNavigationDrawer = true,
  });

  final Widget? appMenu;
  final Widget? navigationDrawer;
  final VoidCallback? onBackToSmarana;
  final ValueChanged<int>? onNavigateToTab;
  final VoidCallback? onWorkspaceChanged;
  final Future<void> Function()? onOpenSettings;
  final Future<void> Function()? onOpenHelp;
  final List<Notebook>? initialNotebooks;
  final NoteWorkspaceStorage? workspaceStorage;
  final bool useInternalNavigationDrawer;

  @override
  State<NotesScreen> createState() => NotesScreenState();
}

class NotesScreenState extends State<NotesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final NoteWorkspaceStorage _workspaceStorage;
  late final ReminderStorage _reminderStorage;
  late final NoteAttachmentStorage _attachmentStorage;
  late List<Notebook> _notebooks;
  Map<String, Reminder> _remindersById = const {};
  Map<String, NoteCardColor> _tagColors = const {};
  Future<void>? _workspaceLoadFuture;
  bool _isLoading = true;
  String? _storageError;
  String? _selectedLabel;
  bool _isGridView = true;
  _NotesSortOrder _sortOrder = _NotesSortOrder.recommended;
  _NotesDestination _destination = _NotesDestination.notes;
  List<RecentNoteView>? _recentNotesCache;
  List<Notebook>? _recentNotesNotebookSource;
  Map<String, NoteCardColor>? _recentNotesTagColorSource;
  Map<String, Reminder>? _recentNotesReminderSource;
  DateTime? _recentNotesCacheExpiresAt;
  List<RecentNoteView>? _filteredRecentNotesCache;
  List<RecentNoteView>? _filteredRecentNotesSource;
  String? _filteredQuery;
  String? _filteredLabel;
  _NotesSortOrder? _filteredSortOrder;
  _NotesDestination? _filteredDestination;

  static const Duration _recentUpdateWindow = Duration(days: 7);

  static const List<Notebook> _emptyNotebookList = [];

  @override
  void initState() {
    super.initState();
    _workspaceStorage = widget.workspaceStorage ?? NoteWorkspaceStorage();
    _reminderStorage = ReminderStorage();
    _attachmentStorage = NoteAttachmentStorage();
    _notebooks = ensureDistinctNotebookColors(
      ensureQuickNotesNotebook(widget.initialNotebooks ?? _emptyNotebookList),
    );
    unawaited(_loadReminderIndex());
    if (widget.initialNotebooks != null) {
      _isLoading = false;
    } else {
      final load = _loadWorkspace();
      _workspaceLoadFuture = load;
      unawaited(load);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  String get _query => _searchController.text.trim().toLowerCase();

  List<String> get _labels {
    final labels = <String, String>{};
    for (final key in _tagColors.keys) {
      final normalized = key.trim().toLowerCase();
      if (normalized.isNotEmpty) {
        labels.putIfAbsent(normalized, () => key.trim());
      }
    }
    for (final notebook in _notebooks) {
      for (final note in notebook.notes) {
        for (final tag in note.projectMetadata?.tags ?? const <String>[]) {
          final normalized = tag.trim().toLowerCase();
          if (normalized.isNotEmpty) {
            labels[normalized] = tag.trim();
          }
        }
      }
    }
    return labels.values.toList()..sort(
      (first, second) => first.toLowerCase().compareTo(second.toLowerCase()),
    );
  }

  Future<void> _loadWorkspace() async {
    try {
      final saved = await _workspaceStorage.loadWorkspace();
      final tagColors = await _workspaceStorage.loadTagColors();
      if (!mounted) {
        return;
      }
      setState(() {
        _notebooks = saved;
        _tagColors = tagColors;
        _isLoading = false;
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _storageError = 'Notes could not be restored. Changes may not persist.';
      });
      developer.log('Notes workspace restore failed', error: error);
    }
  }

  Future<bool> _persistWorkspace() async {
    try {
      await _workspaceStorage.saveWorkspace(_notebooks, tagColors: _tagColors);
      if (mounted) widget.onWorkspaceChanged?.call();
      if (mounted && _storageError != null) {
        setState(() {
          _storageError = null;
        });
      }
      return true;
    } on Exception catch (error) {
      if (!mounted) {
        return false;
      }
      setState(() {
        _storageError = 'Notes could not be saved. Check device storage.';
      });
      developer.log('Notes workspace save failed', error: error);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notes could not be saved.')),
      );
      return false;
    }
  }

  Future<void> _updateTagColors(Map<String, NoteCardColor> tagColors) async {
    setState(() {
      _tagColors = Map<String, NoteCardColor>.unmodifiable(tagColors);
    });
    if (widget.initialNotebooks == null) {
      await _persistWorkspace();
    }
  }

  Future<void> _changeTagColor(String tag, NoteCardColor color) {
    final updated = Map<String, NoteCardColor>.of(_tagColors)
      ..[tag.trim().toLowerCase()] = color;
    return _updateTagColors(updated);
  }

  Future<void> _updateNotebook(Notebook updated) async {
    setState(() {
      _notebooks = _notebooks.map((item) {
        return item.id == updated.id ? updated : item;
      }).toList();
    });
    if (widget.initialNotebooks == null) {
      await _persistWorkspace();
    }
  }

  List<RecentNoteView> get _filteredRecentNotes {
    final query = _query;
    final recentNotes = _recentNotes();
    final cachedNotes = _filteredRecentNotesCache;
    if (cachedNotes != null &&
        identical(_filteredRecentNotesSource, recentNotes) &&
        _filteredQuery == query &&
        _filteredLabel == _selectedLabel &&
        _filteredSortOrder == _sortOrder &&
        _filteredDestination == _destination) {
      return cachedNotes;
    }

    final filteredNotes = recentNotes.where((note) {
      if (_destination == _NotesDestination.archive) {
        if (!note.note.isArchived) {
          return false;
        }
      } else if (note.note.isArchived) {
        return false;
      }
      if (_selectedLabel != null &&
          !(note.note.projectMetadata?.tags.any(
                (tag) => tag.trim().toLowerCase() == _selectedLabel,
              ) ??
              false)) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return note.note.title.toLowerCase().contains(query) ||
          note.note.preview.toLowerCase().contains(query) ||
          (note.note.projectMetadata?.tags.any(
                (tag) => tag.toLowerCase().contains(query),
              ) ??
              false);
    }).toList();
    switch (_sortOrder) {
      case _NotesSortOrder.recommended:
        break;
      case _NotesSortOrder.recentlyUpdated:
        filteredNotes.sort(
          (first, second) =>
              second.note.updatedAt.compareTo(first.note.updatedAt),
        );
      case _NotesSortOrder.title:
        filteredNotes.sort(
          (first, second) => first.note.title.toLowerCase().compareTo(
            second.note.title.toLowerCase(),
          ),
        );
    }
    _filteredRecentNotesCache = filteredNotes;
    _filteredRecentNotesSource = recentNotes;
    _filteredQuery = query;
    _filteredLabel = _selectedLabel;
    _filteredSortOrder = _sortOrder;
    _filteredDestination = _destination;
    return filteredNotes;
  }

  List<RecentNoteView> _recentNotes() {
    final now = DateTime.now();
    final cachedNotes = _recentNotesCache;
    final cacheExpiresAt = _recentNotesCacheExpiresAt;
    if (cachedNotes != null &&
        identical(_recentNotesNotebookSource, _notebooks) &&
        identical(_recentNotesTagColorSource, _tagColors) &&
        identical(_recentNotesReminderSource, _remindersById) &&
        (cacheExpiresAt == null || now.isBefore(cacheExpiresAt))) {
      return cachedNotes;
    }

    final views = <RecentNoteView>[];
    DateTime? nextPriorityChange;
    for (final notebook in _notebooks) {
      for (final note in notebook.notes) {
        final priorityChange = note.updatedAt.add(_recentUpdateWindow);
        if (priorityChange.isAfter(now) &&
            (nextPriorityChange == null ||
                priorityChange.isBefore(nextPriorityChange))) {
          nextPriorityChange = priorityChange;
        }
        views.add(
          RecentNoteView(
            note: note,
            notebookId: notebook.id,
            notebookIconType: notebook.iconType,
            notebookName: notebook.name,
            notebookIcon: notebook.icon,
            notebookColorValue: notebook.colorValue,
            tagColors: _tagColors,
          ),
        );
      }
    }
    views.sort((first, second) => _compareNotes(first, second, now));
    _recentNotesCache = views;
    _recentNotesNotebookSource = _notebooks;
    _recentNotesTagColorSource = _tagColors;
    _recentNotesReminderSource = _remindersById;
    _recentNotesCacheExpiresAt = nextPriorityChange;
    return views;
  }

  int _compareNotes(RecentNoteView first, RecentNoteView second, DateTime now) {
    final firstPriority = _notePriority(first, now);
    final secondPriority = _notePriority(second, now);
    final priorityComparison = firstPriority.compareTo(secondPriority);
    if (priorityComparison != 0) {
      return priorityComparison;
    }

    if (firstPriority == 2) {
      final firstReminder = _activeReminderFor(first);
      final secondReminder = _activeReminderFor(second);
      if (firstReminder != null && secondReminder != null) {
        final reminderComparison = firstReminder.dateTime.compareTo(
          secondReminder.dateTime,
        );
        if (reminderComparison != 0) {
          return reminderComparison;
        }
      }
    }

    return second.note.updatedAt.compareTo(first.note.updatedAt);
  }

  int _notePriority(RecentNoteView note, DateTime now) {
    if (note.note.isPinned) {
      return 0;
    }
    if (note.note.updatedAt.isAfter(now.subtract(_recentUpdateWindow))) {
      return 1;
    }
    if (_activeReminderFor(note) != null) {
      return 2;
    }
    return 3;
  }

  Reminder? _activeReminderFor(RecentNoteView note) {
    final reminderId = note.note.reminderId;
    if (reminderId == null) {
      return null;
    }
    final reminder = _remindersById[reminderId];
    if (reminder == null || !reminder.enabled || reminder.isCompleted) {
      return null;
    }
    return reminder;
  }

  Future<void> _loadReminderIndex() async {
    try {
      final reminders = await _reminderStorage.getReminders();
      if (!mounted) {
        return;
      }
      setState(() {
        _remindersById = {
          for (final reminder in reminders) reminder.id: reminder,
        };
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _storageError ??= 'Reminder dates could not be loaded. Notes are sorted by update time.';
      });
      developer.log('Notes reminder index restore failed', error: error);
    }
  }

  Future<void> _openRecentNote(RecentNoteView recentNote) async {
    await _openNoteEditor(recentNote.note);
  }

  Future<void> openNotebookById(String notebookId) async {
    await _waitForWorkspace();
    if (!mounted) return;
    final notebooks = _notebooks.where((notebook) => notebook.id == notebookId);
    if (notebooks.isEmpty) return;
    final notebook = notebooks.first;
    await Navigator.of(context).push<NotebookDetailResult>(
      MaterialPageRoute<NotebookDetailResult>(
        builder: (_) => NotebookDetailScreen(
          notebook: notebook,
          notebooks: _notebooks,
          navigationDrawer: widget.navigationDrawer,
          reminderStorage: _reminderStorage,
          tagColors: _tagColors,
          onTagColorsChanged: _updateTagColors,
          onNotebookChanged: _updateNotebook,
          onNoteChanged: _saveNote,
          onNoteDeleted: _deleteNote,
        ),
      ),
    );
  }

  Future<void> openNoteById(String notebookId, String noteId) async {
    await _waitForWorkspace();
    if (!mounted) return;
    final matches = _notebooks
        .where((notebook) => notebook.id == notebookId)
        .expand((notebook) => notebook.notes)
        .where((note) => note.id == noteId);
    if (matches.isNotEmpty) {
      await _openNoteEditor(matches.first);
    }
  }

  Future<void> _waitForWorkspace() async {
    if (_isLoading) await _workspaceLoadFuture;
  }

  void _retryLoadWorkspace() {
    final load = _loadWorkspace();
    _workspaceLoadFuture = load;
    unawaited(load);
  }

  void focusSearch() {
    setState(() {
      _destination = _NotesDestination.notes;
      _selectedLabel = null;
    });
    _searchFocusNode.requestFocus();
  }

  void searchFor(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.collapsed(offset: query.length);
    setState(() {
      _destination = _NotesDestination.notes;
      _selectedLabel = null;
    });
  }

  Future<void> _togglePinnedNote(RecentNoteView recentNote) async {
    final notebookIndex = _notebooks.indexWhere(
      (notebook) => notebook.id == recentNote.notebookId,
    );
    if (notebookIndex == -1) {
      return;
    }
    final notebook = _notebooks[notebookIndex];
    final updated = notebook.copyWith(
      notes: notebook.notes
          .map(
            (note) => note.id == recentNote.note.id
                ? note.copyWith(isPinned: !note.isPinned)
                : note,
          )
          .toList(),
      updatedAt: DateTime.now(),
    );
    await _updateNotebook(updated);
  }

  Future<void> _changeNoteColor(
    RecentNoteView recentNote,
    NoteCardColor color,
  ) async {
    final notebookIndex = _notebooks.indexWhere(
      (notebook) => notebook.id == recentNote.notebookId,
    );
    if (notebookIndex == -1) {
      return;
    }
    final notebook = _notebooks[notebookIndex];
    final now = DateTime.now();
    final updated = notebook.copyWith(
      notes: notebook.notes
          .map(
            (note) => note.id == recentNote.note.id
                ? note.copyWith(color: color, updatedAt: now)
                : note,
          )
          .toList(),
      updatedAt: now,
    );
    await _updateNotebook(updated);
  }

  Future<bool> _saveNote(NoteEntry note) async {
    final destinationExists = _notebooks.any(
      (notebook) => notebook.id == note.notebookId,
    );
    if (!destinationExists) {
      throw StateError('The selected notebook is no longer available.');
    }

    final isNewNote = !_notebooks.any(
      (notebook) => notebook.notes.any((existing) => existing.id == note.id),
    );
    final now = note.updatedAt;
    final updatedNotebooks = _notebooks.map((notebook) {
      final alreadyContains = notebook.notes.any(
        (existing) => existing.id == note.id,
      );
      if (!alreadyContains && notebook.id != note.notebookId) {
        return notebook;
      }
      final notes = notebook.notes
          .where((existing) => existing.id != note.id)
          .toList();
      if (notebook.id == note.notebookId) {
        notes.add(note);
      }
      return notebook.copyWith(notes: notes, updatedAt: now);
    }).toList();
    final previousNotebooks = _notebooks;
    setState(() {
      _notebooks = updatedNotebooks;
    });
    if (widget.initialNotebooks == null) {
      final saved = await _persistWorkspace();
      if (!saved) {
        if (mounted && identical(_notebooks, updatedNotebooks)) {
          setState(() {
            _notebooks = previousNotebooks;
          });
        }
        return false;
      }
      if (saved && isNewNote) {
        unawaited(AnalyticsService.instance.logNoteCreated());
      }
    }
    return true;
  }

  Future<void> _deleteNote(String noteId) async {
    final updatedNotebooks = _notebooks.map((notebook) {
      if (!notebook.notes.any((note) => note.id == noteId)) {
        return notebook;
      }
      return notebook.copyWith(
        notes: notebook.notes.where((note) => note.id != noteId).toList(),
        updatedAt: DateTime.now(),
      );
    }).toList();
    setState(() {
      _notebooks = updatedNotebooks;
    });
    if (widget.initialNotebooks == null) {
      await _persistWorkspace();
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

  Future<void> _createLabel() async {
    final label = await showDialog<String>(
      context: context,
      builder: (context) => const _LabelNameDialog(),
    );
    final trimmed = label?.trim();
    if (trimmed == null || trimmed.isEmpty || !mounted) {
      return;
    }
    final normalized = trimmed.toLowerCase();
    if (_labels.any((existing) => existing.toLowerCase() == normalized)) {
      setState(() {
        _selectedLabel = normalized;
        _destination = _NotesDestination.notes;
      });
      return;
    }
    await _changeTagColor(trimmed, nextBalancedTagColor(_tagColors.values));
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedLabel = normalized;
      _destination = _NotesDestination.notes;
    });
  }

  void _selectDrawerDestination(_NotesDestination destination) {
    setState(() {
      _destination = destination;
      _selectedLabel = null;
    });
    Navigator.of(context).pop();
  }

  void _selectFilterDestination(_NotesDestination destination) {
    setState(() {
      _destination = destination;
      _selectedLabel = null;
    });
  }

  Widget _buildFilterChips(BuildContext context) {
    final label = _selectedLabel;
    return SingleChildScrollView(
      key: const ValueKey('notes-filter-chips'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            key: const ValueKey('notes-filter-all'),
            label: const Text('All notes'),
            selected: _destination == _NotesDestination.notes && label == null,
            onSelected: (_) => _selectFilterDestination(_NotesDestination.notes),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            key: const ValueKey('notes-filter-archive'),
            label: const Text('Archive'),
            selected: _destination == _NotesDestination.archive,
            onSelected: (_) =>
                _selectFilterDestination(_NotesDestination.archive),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            key: const ValueKey('notes-filter-deleted'),
            label: const Text('Deleted'),
            selected: _destination == _NotesDestination.deleted,
            onSelected: (_) =>
                _selectFilterDestination(_NotesDestination.deleted),
          ),
          if (label != null) ...[
            const SizedBox(width: 8),
            InputChip(
              key: const ValueKey('notes-filter-label'),
              avatar: const Icon(Icons.label_outline_rounded, size: 18),
              label: Text(_labelName(label)),
              selected: true,
              onDeleted: () => _selectFilterDestination(_NotesDestination.notes),
              deleteButtonTooltipMessage: 'Clear label filter',
            ),
          ],
        ],
      ),
    );
  }

  void _selectLabel(String label) {
    setState(() {
      _destination = _NotesDestination.notes;
      _selectedLabel = label.toLowerCase();
    });
    Navigator.of(context).pop();
  }

  String _labelName(String value) {
    final label = _labels.firstWhere(
      (item) => item.toLowerCase() == value,
      orElse: () => value,
    );
    if (label.isEmpty) {
      return label;
    }
    return '${label[0].toUpperCase()}${label.substring(1)}';
  }

  void _navigateToTab(int index) {
    Navigator.of(context).pop();
    final onNavigateToTab = widget.onNavigateToTab;
    if (onNavigateToTab != null) {
      onNavigateToTab(index);
    } else if (index == 0) {
      widget.onBackToSmarana?.call();
    }
  }

  Future<void> _openDrawerAction(Future<void> Function()? action) async {
    Navigator.of(context).pop();
    await action?.call();
  }

  void _handleQuickCreate(NotesQuickCreateAction action) {
    switch (action) {
      case NotesQuickCreateAction.image:
        unawaited(_createNote(pickImageOnOpen: true));
        break;
      case NotesQuickCreateAction.drawing:
        _showQuickCreateUnavailable('Drawing notes are not available yet.');
        break;
      case NotesQuickCreateAction.audio:
        _showQuickCreateUnavailable('Audio recording is not available yet.');
        break;
      case NotesQuickCreateAction.list:
        unawaited(_createNote(startWithChecklist: true));
        break;
      case NotesQuickCreateAction.text:
        unawaited(_createNote());
        break;
    }
  }

  void _showQuickCreateUnavailable(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createNote({
    bool startWithChecklist = false,
    bool pickImageOnOpen = false,
  }) async {
    final notebook = _notebooks.firstWhere(isDefaultNotebook);
    final now = DateTime.now();
    final note = NoteEntry(
      id: _id('note'),
      notebookId: notebook.id,
      title: '',
      content: '',
      createdAt: now,
      updatedAt: now,
      color: nextBalancedNoteColor(notebook.notes),
    );
    await _openNoteEditor(
      note,
      focusOnOpen: true,
      startWithChecklist: startWithChecklist,
      pickImageOnOpen: pickImageOnOpen,
    );
  }

  Future<void> _openNoteEditor(
    NoteEntry note, {
    bool focusOnOpen = false,
    bool startWithChecklist = false,
    bool pickImageOnOpen = false,
  }) async {
    final draft = await Navigator.of(context).push<RichNoteDraft>(
      MaterialPageRoute<RichNoteDraft>(
        builder: (_) => RichNoteEditorScreen(
          note: note,
          notebooks: _notebooks,
          focusOnOpen: focusOnOpen,
          startWithChecklist: startWithChecklist,
          pickImageOnOpen: pickImageOnOpen,
          tagColors: _tagColors,
          onTagColorsChanged: _updateTagColors,
          reminderStorage: _reminderStorage,
          navigationDrawer: widget.navigationDrawer,
          onAutosave: (snapshot) async {
            if (snapshot.title.trim().isEmpty &&
                snapshot.plainContent.trim().isEmpty &&
                snapshot.attachments.isEmpty &&
                !snapshot.isPinned &&
                !snapshot.isArchived &&
                !startWithChecklist) {
              return;
            }
            final saved = await _saveNote(
              _noteFromDraft(base: note, draft: snapshot),
            );
            if (!saved) {
              throw Exception('Notes workspace save failed.');
            }
          },
          onPinChanged: (snapshot) async {
            await _saveNote(_noteFromDraft(base: note, draft: snapshot));
          },
          onArchiveChanged: (snapshot) async {
            await _saveNote(_noteFromDraft(base: note, draft: snapshot));
          },
          onDuplicate: (snapshot) async {
            final id = _id('note');
            final attachments = await _attachmentStorage.duplicateAttachments(
              attachments: snapshot.attachments,
              noteId: id,
            );
            final title = snapshot.title.trim().isEmpty
                ? 'Untitled'
                : snapshot.title.trim();
            await _saveNote(
              NoteEntry(
                id: id,
                notebookId: snapshot.notebookId,
                title: '$title copy',
                content: snapshot.plainContent,
                richContentDelta: snapshot.richContentDelta,
                attachments: attachments,
                projectMetadata: snapshot.projectMetadata,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
                color: snapshot.color,
                textColor: snapshot.textColor,
              ),
            );
          },
          onDelete: (snapshot) async {
            final reminderId = snapshot.reminderId;
            if (reminderId != null) {
              await _reminderStorage.deleteReminder(reminderId);
            }
            await _deleteNote(note.id);
          },
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (draft != null &&
        (draft.title.trim().isNotEmpty ||
            draft.plainContent.trim().isNotEmpty ||
            draft.attachments.isNotEmpty ||
            draft.isPinned ||
            draft.isArchived ||
            startWithChecklist)) {
      await _saveNote(_noteFromDraft(base: note, draft: draft));
    } else if (draft?.reminderId != null) {
      await _reminderStorage.deleteReminder(draft!.reminderId!);
    }
  }

  String _id(String prefix) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: widget.useInternalNavigationDrawer
          ? widget.navigationDrawer ?? _buildNavigationDrawer(context)
          : null,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 52,
        leading: Builder(
          builder: (context) => IconButton(
            key: const ValueKey('notes-drawer-button'),
            tooltip: 'Open navigation menu',
            onPressed: () => AppNavigationDrawerHost.openDrawer(context),
            icon: const Icon(Icons.menu_rounded),
          ),
        ),
        titleSpacing: 0,
        title: _buildSearchBar(context),
        actions: [
          IconButton(
            key: const ValueKey('notes-view-toggle'),
            tooltip: _isGridView
                ? 'Switch to list view'
                : 'Switch to grid view',
            onPressed: () => setState(() => _isGridView = !_isGridView),
            icon: Icon(
              _isGridView
                  ? Icons.view_agenda_outlined
                  : Icons.grid_view_outlined,
            ),
          ),
          PopupMenuButton<_NotesSortOrder>(
            key: const ValueKey('notes-sort-menu'),
            tooltip: 'Sort notes',
            initialValue: _sortOrder,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            onSelected: (order) => setState(() => _sortOrder = order),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _NotesSortOrder.recommended,
                child: Text('Recommended'),
              ),
              PopupMenuItem(
                value: _NotesSortOrder.recentlyUpdated,
                child: Text('Recently updated'),
              ),
              PopupMenuItem(value: _NotesSortOrder.title, child: Text('Title')),
            ],
            icon: const Icon(Icons.swap_vert_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState(context)
          : SafeArea(
              top: false,
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_storageError != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: MaterialBanner(
                                content: Text(_storageError!),
                                leading: const Icon(
                                  Icons.warning_amber_rounded,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: _retryLoadWorkspace,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          _buildFilterChips(context),
                          const SizedBox(height: 12),
                          if (_destination == _NotesDestination.notes) ...[
                            _buildRecentNotesSection(
                              context,
                              maxWidth: constraints.maxWidth,
                            ),
                          ] else if (_destination ==
                              _NotesDestination.archive) ...[
                            Text(
                              'Archive',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            _buildRecentNotesSection(
                              context,
                              maxWidth: constraints.maxWidth,
                            ),
                          ] else
                            _buildDestinationState(context),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
      floatingActionButton: _destination == _NotesDestination.notes
          ? NotesHomeQuickCreateMenu(onAction: _handleQuickCreate)
          : null,
    );
  }

  Widget _buildNavigationDrawer(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget divider() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
    );

    return Drawer(
      backgroundColor: colorScheme.surface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              child: Row(
                children: [
                  Icon(
                    Icons.sticky_note_2_rounded,
                    color: colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Total Reminders',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _drawerItem(
              context,
              key: const ValueKey('notes-drawer-notes'),
              icon: Icons.sticky_note_2_outlined,
              label: 'Notes',
              selected:
                  _destination == _NotesDestination.notes &&
                  _selectedLabel == null,
              onTap: () => _selectDrawerDestination(_NotesDestination.notes),
            ),
            _drawerItem(
              context,
              key: const ValueKey('notes-drawer-calendar'),
              icon: Icons.calendar_month_outlined,
              label: 'Calendar',
              selected: false,
              onTap: () => _navigateToTab(0),
            ),
            _drawerItem(
              context,
              key: const ValueKey('notes-drawer-reminders'),
              icon: Icons.notifications_none_rounded,
              label: 'Reminders',
              selected: false,
              onTap: () => _navigateToTab(2),
            ),
            divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Labels',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final label in _labels)
              _drawerItem(
                context,
                key: ValueKey('notes-drawer-label-${label.toLowerCase()}'),
                icon: Icons.label_outline_rounded,
                label: label,
                selected: _selectedLabel == label.toLowerCase(),
                onTap: () => _selectLabel(label),
              ),
            _drawerItem(
              context,
              key: const ValueKey('notes-drawer-create-label'),
              icon: Icons.add_rounded,
              label: 'Create new label',
              selected: false,
              onTap: () async {
                Navigator.of(context).pop();
                await _createLabel();
              },
            ),
            divider(),
            _drawerItem(
              context,
              key: const ValueKey('notes-drawer-archive'),
              icon: Icons.archive_outlined,
              label: 'Archive',
              selected: _destination == _NotesDestination.archive,
              onTap: () => _selectDrawerDestination(_NotesDestination.archive),
            ),
            _drawerItem(
              context,
              key: const ValueKey('notes-drawer-deleted'),
              icon: Icons.delete_outline_rounded,
              label: 'Deleted',
              selected: _destination == _NotesDestination.deleted,
              onTap: () => _selectDrawerDestination(_NotesDestination.deleted),
            ),
            _drawerItem(
              context,
              key: const ValueKey('notes-drawer-settings'),
              icon: Icons.settings_outlined,
              label: 'Settings',
              selected: false,
              onTap: () => _openDrawerAction(widget.onOpenSettings),
            ),
            _drawerItem(
              context,
              key: const ValueKey('notes-drawer-help'),
              icon: Icons.help_outline_rounded,
              label: 'Help',
              selected: false,
              onTap: () => _openDrawerAction(widget.onOpenHelp),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ListTile(
      key: key,
      minLeadingWidth: 24,
      horizontalTitleGap: 16,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      selected: selected,
      selectedTileColor: colorScheme.primary.withValues(
        alpha: theme.brightness == Brightness.light ? 0.12 : 0.2,
      ),
      leading: Icon(
        icon,
        color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      title: Text(
        label,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? colorScheme.primary : colorScheme.onSurface,
        ),
      ),
      onTap: onTap,
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text('Loading notes workspace...', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextField(
      key: const ValueKey('notes-workspace-search'),
      controller: _searchController,
      focusNode: _searchFocusNode,
      decoration: InputDecoration(
        hintText: 'Search notes',
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.2),
        ),
        suffixIcon: IconButton(
          tooltip: 'Clear search',
          onPressed: _query.isEmpty
              ? null
              : () {
                  _searchController.clear();
                  setState(() {});
                },
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildRecentNotesSection(
    BuildContext context, {
    required double maxWidth,
  }) {
    final notes = _filteredRecentNotes;
    final crossAxisCount = maxWidth < 600
        ? 2
        : ((maxWidth - 22) / 230).floor().clamp(2, 5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notes.isEmpty)
          _buildRecentNotesContent(
            context,
            key: ValueKey(
              'notes-content-${_selectedLabel ?? _destination.name}-empty',
            ),
            child: _SectionEmptyState(
              message: _selectedLabel != null
                  ? 'No notes with the "${_labelName(_selectedLabel!)}" label.'
                  : _destination == _NotesDestination.archive
                  ? 'No archived notes.'
                  : _query.isEmpty
                  ? 'No notes yet. Create a note to get started.'
                  : 'No notes match your search.',
            ),
          )
        else
          _buildRecentNotesContent(
            context,
            key: ValueKey(
              'notes-content-${_selectedLabel ?? _destination.name}-notes-${_isGridView ? 'grid' : 'list'}',
            ),
            child: _isGridView
                ? GridView.builder(
                    key: const ValueKey('notes-grid-view'),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: notes.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisExtent: 176,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemBuilder: (context, index) =>
                        _buildNoteCard(notes[index], compact: true),
                  )
                : ListView.separated(
                    key: const ValueKey('notes-list-view'),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: notes.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 6),
                    itemBuilder: (context, index) => SizedBox(
                      height: 176,
                      child: _buildNoteCard(notes[index], compact: false),
                    ),
                  ),
          ),
      ],
    );
  }

  Widget _buildNoteCard(RecentNoteView note, {required bool compact}) {
    return Semantics(
      button: true,
      label: 'Open ${note.note.title}',
      child: RecentNoteCard(
        note: note,
        compact: compact,
        onTap: () => _openRecentNote(note),
        onTogglePinned: () => _togglePinnedNote(note),
        onColorChanged: (color) => _changeNoteColor(note, color),
        onTagColorChanged: _changeTagColor,
      ),
    );
  }

  Widget _buildDestinationState(BuildContext context) {
    final isArchive = _destination == _NotesDestination.archive;
    return _SectionEmptyState(
      message: isArchive
          ? 'Archived notes will appear here.'
          : 'Deleted notes will appear here.',
    );
  }

  Widget _buildRecentNotesContent(
    BuildContext context, {
    required Key key,
    required Widget child,
  }) {
    return AnimatedSwitcher(
      duration: AppMotion.resolve(context, AppMotion.interaction),
      switchInCurve: AppMotion.enter,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: key, child: child),
    );
  }
}

class _SectionEmptyState extends StatelessWidget {
  const _SectionEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _LabelNameDialog extends StatefulWidget {
  const _LabelNameDialog();

  @override
  State<_LabelNameDialog> createState() => _LabelNameDialogState();
}

class _LabelNameDialogState extends State<_LabelNameDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create new label'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Label name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
