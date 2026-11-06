import 'package:flutter/material.dart';

enum NoteEditorInsertAction {
  takePhoto,
  addImage,
  recording,
  drawing,
  tickBoxes,
  table,
}

enum NoteEditorMoreAction {
  findInNote,
  delete,
  makeCopy,
  send,
  collaborator,
  labels,
  helpAndFeedback,
}

class NoteEditorInsertSheet extends StatelessWidget {
  const NoteEditorInsertSheet({super.key});

  static Future<NoteEditorInsertAction?> show(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return showModalBottomSheet<NoteEditorInsertAction>(
      context: context,
      useSafeArea: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => const NoteEditorInsertSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in _insertActions)
                ListTile(
                  minVerticalPadding: 12,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 28),
                  leading: Icon(item.$2),
                  title: Text(item.$1),
                  onTap: () => Navigator.of(context).pop(item.$3),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const _insertActions = [
  ('Take photo', Icons.photo_camera_outlined, NoteEditorInsertAction.takePhoto),
  ('Add image', Icons.image_outlined, NoteEditorInsertAction.addImage),
  ('Recording', Icons.mic_none_rounded, NoteEditorInsertAction.recording),
  ('Drawing', Icons.brush_outlined, NoteEditorInsertAction.drawing),
  ('Tick boxes', Icons.check_box_outlined, NoteEditorInsertAction.tickBoxes),
  ('Insert table', Icons.table_chart_outlined, NoteEditorInsertAction.table),
];

class NoteEditorMoreSheet extends StatelessWidget {
  const NoteEditorMoreSheet({required this.editedAt, super.key});

  final DateTime editedAt;

  static Future<NoteEditorMoreAction?> show(
    BuildContext context, {
    required DateTime editedAt,
  }) {
    final colors = Theme.of(context).colorScheme;
    return showModalBottomSheet<NoteEditorMoreAction>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => NoteEditorMoreSheet(editedAt: editedAt),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final dateLabel = localizations.formatShortDate(editedAt);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 12, 12),
                  child: Text(
                    'Edited $dateLabel',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              for (final (label, icon, action) in _moreActions)
                ListTile(
                  minVerticalPadding: 10,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: Icon(
                    icon,
                    color: action == NoteEditorMoreAction.delete
                        ? colors.error
                        : colors.onSurface,
                  ),
                  title: Text(
                    label,
                    style: TextStyle(
                      color: action == NoteEditorMoreAction.delete
                          ? colors.error
                          : colors.onSurface,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(action),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const _moreActions = [
  ('Find in note', Icons.search_rounded, NoteEditorMoreAction.findInNote),
  ('Delete', Icons.delete_outline_rounded, NoteEditorMoreAction.delete),
  ('Make a copy', Icons.copy_all_outlined, NoteEditorMoreAction.makeCopy),
  ('Send', Icons.ios_share_rounded, NoteEditorMoreAction.send),
  (
    'Collaborator',
    Icons.person_add_alt_1_rounded,
    NoteEditorMoreAction.collaborator,
  ),
  ('Labels', Icons.sell_outlined, NoteEditorMoreAction.labels),
  (
    'Help & feedback',
    Icons.help_outline_rounded,
    NoteEditorMoreAction.helpAndFeedback,
  ),
];
