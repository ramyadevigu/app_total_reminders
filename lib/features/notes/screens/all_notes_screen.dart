import 'package:flutter/material.dart';

import '../models/note_workspace_models.dart';
import '../widgets/recent_note_card.dart';

class AllNotesScreen extends StatefulWidget {
  const AllNotesScreen({
    super.key,
    required this.notes,
    required this.onTogglePinned,
    required this.onColorChanged,
    required this.onTagColorChanged,
  });

  final List<RecentNoteView> notes;
  final Future<void> Function(RecentNoteView note) onTogglePinned;
  final Future<void> Function(RecentNoteView note, NoteCardColor color)
  onColorChanged;
  final Future<void> Function(String tag, NoteCardColor color)
  onTagColorChanged;

  @override
  State<AllNotesScreen> createState() => _AllNotesScreenState();
}

class _AllNotesScreenState extends State<AllNotesScreen> {
  late List<RecentNoteView> _notes;
  Map<String, NoteCardColor> _tagColors = const {};

  @override
  void initState() {
    super.initState();
    _notes = List<RecentNoteView>.of(widget.notes);
    if (_notes.isNotEmpty) {
      _tagColors = _notes.first.tagColors;
    }
  }

  Future<void> _togglePinned(RecentNoteView note) async {
    await widget.onTogglePinned(note);
    if (!mounted) {
      return;
    }
    _replaceNote(note, note.note.copyWith(isPinned: !note.note.isPinned));
  }

  Future<void> _changeNoteColor(
    RecentNoteView note,
    NoteCardColor color,
  ) async {
    await widget.onColorChanged(note, color);
    if (!mounted) {
      return;
    }
    _replaceNote(
      note,
      note.note.copyWith(color: color, updatedAt: DateTime.now()),
    );
  }

  Future<void> _changeTagColor(String tag, NoteCardColor color) async {
    await widget.onTagColorChanged(tag, color);
    if (!mounted) {
      return;
    }
    setState(() {
      _tagColors = {..._tagColors, tag.trim().toLowerCase(): color};
      _notes = _notes
          .map(
            (note) => RecentNoteView(
              note: note.note,
              notebookId: note.notebookId,
              notebookIconType: note.notebookIconType,
              notebookName: note.notebookName,
              notebookIcon: note.notebookIcon,
              notebookColorValue: note.notebookColorValue,
              tagColors: _tagColors,
            ),
          )
          .toList();
    });
  }

  void _replaceNote(RecentNoteView previous, NoteEntry updatedNote) {
    setState(() {
      _notes = _notes
          .map(
            (note) => note.note.id == previous.note.id
                ? RecentNoteView(
                    note: updatedNote,
                    notebookId: note.notebookId,
                    notebookIconType: note.notebookIconType,
                    notebookName: note.notebookName,
                    notebookIcon: note.notebookIcon,
                    notebookColorValue: note.notebookColorValue,
                    tagColors: _tagColors,
                  )
                : note,
          )
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('All Notes')),
      body: _notes.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sticky_note_2_outlined,
                      size: 40,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No notes yet',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Notes you create will appear here.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth >= 720 ? 3 : 2;
                return GridView.builder(
                  key: const ValueKey('all-notes-grid'),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: _notes.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisExtent: 176,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemBuilder: (context, index) {
                    final note = _notes[index];
                    return RecentNoteCard(
                      note: note,
                      compact: true,
                      onTap: () => Navigator.of(context).pop(note),
                      onTogglePinned: () => _togglePinned(note),
                      onColorChanged: (color) => _changeNoteColor(note, color),
                      onTagColorChanged: _changeTagColor,
                    );
                  },
                );
              },
            ),
    );
  }
}
