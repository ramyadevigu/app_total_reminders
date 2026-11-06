import 'package:flutter/material.dart';

import '../models/note_workspace_models.dart';
import '../theme/note_card_colors.dart';

Future<NoteCardColor?> showNoteTagColorPicker(
  BuildContext context, {
  required NoteCardColor current,
}) {
  return _showNoteColorPicker(
    context,
    current: current,
    title: 'Tag Color',
    colorKind: 'tag',
  );
}

Future<NoteCardColor?> showNoteCardColorPicker(
  BuildContext context, {
  required NoteCardColor current,
}) {
  return _showNoteColorPicker(
    context,
    current: current,
    title: 'Note Color',
    colorKind: 'note',
  );
}

Future<NoteCardColor?> _showNoteColorPicker(
  BuildContext context, {
  required NoteCardColor current,
  required String title,
  required String colorKind,
}) {
  return showModalBottomSheet<NoteCardColor>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final color in selectableNoteCardColors)
                  _TagColorSwatch(
                    color: color,
                    selected: color == current,
                    colorKind: colorKind,
                    onTap: () => Navigator.of(context).pop(color),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class NoteTagChip extends StatelessWidget {
  const NoteTagChip({
    super.key,
    required this.label,
    required this.color,
    this.onColorChange,
  });

  final String label;
  final NoteCardColor color;
  final VoidCallback? onColorChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = noteCardAccentColor(theme, color);
    final background = noteTagSurfaceColor(theme, color);
    final avatar = Icon(Icons.sell_outlined, size: 13, color: accent);
    final textStyle = theme.textTheme.labelSmall?.copyWith(color: accent);

    if (onColorChange == null) {
      return Chip(
        avatar: avatar,
        label: Text(label),
        labelStyle: textStyle,
        backgroundColor: background,
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
      );
    }

    return ActionChip(
      tooltip: 'Change $label tag color',
      onPressed: onColorChange,
      avatar: avatar,
      label: Text(label),
      labelStyle: textStyle,
      backgroundColor: background,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
    );
  }
}

class _TagColorSwatch extends StatelessWidget {
  const _TagColorSwatch({
    required this.color,
    required this.selected,
    required this.colorKind,
    required this.onTap,
  });

  final NoteCardColor color;
  final bool selected;
  final String colorKind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = noteCardColorLabel(color);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label $colorKind color${selected ? ', selected' : ''}',
      child: Tooltip(
        message: label,
        child: InkWell(
          key: ValueKey('$colorKind-color-${color.name}'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: noteCardSwatchColor(theme, color),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: selected
                ? Icon(
                    Icons.check_rounded,
                    size: 19,
                    color: noteCardAccentColor(theme, color),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
