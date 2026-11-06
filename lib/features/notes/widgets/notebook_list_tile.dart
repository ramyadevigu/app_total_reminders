import 'package:flutter/material.dart';

import '../models/note_workspace_models.dart';
import '../theme/notebook_colors.dart';

class NotebookListTile extends StatelessWidget {
  const NotebookListTile({
    super.key,
    required this.notebook,
    required this.onOpen,
    required this.onOptions,
    required this.selected,
  });

  final Notebook notebook;
  final VoidCallback onOpen;
  final VoidCallback onOptions;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accentColor = notebookAccentColor(theme, notebook.colorValue);
    final foregroundColor = notebookForegroundColor(theme, notebook.colorValue);
    final borderRadius = BorderRadius.circular(14);
    final description = notebook.description.trim();

    return Semantics(
      button: true,
      selected: selected,
      label: '${notebook.name}, ${notebook.noteCount} notes',
      onLongPress: onOptions,
      child: Material(
        color: notebookSurfaceColor(theme, notebook.colorValue),
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(
            color: selected ? accentColor : colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onOpen,
          onLongPress: onOptions,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(
                  notebookIconData(notebook.icon, notebook.iconType),
                  size: 26,
                  color: accentColor,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        notebook.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: accentColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description.isEmpty
                            ? '${notebook.noteCount} notes'
                            : description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: foregroundColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 2),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected)
                      Icon(
                        Icons.check_circle_rounded,
                        size: 17,
                        color: accentColor,
                      )
                    else
                      const SizedBox(height: 17),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        tooltip: 'Notebook options for ${notebook.name}',
                        padding: EdgeInsets.zero,
                        onPressed: onOptions,
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          size: 19,
                          color: foregroundColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
