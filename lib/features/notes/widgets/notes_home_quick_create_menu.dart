import 'package:flutter/material.dart';

enum NotesQuickCreateAction { image, drawing, audio, list, text }

class NotesHomeQuickCreateMenu extends StatefulWidget {
  const NotesHomeQuickCreateMenu({required this.onAction, super.key});

  final ValueChanged<NotesQuickCreateAction> onAction;

  @override
  State<NotesHomeQuickCreateMenu> createState() =>
      _NotesHomeQuickCreateMenuState();
}

class _NotesHomeQuickCreateMenuState extends State<NotesHomeQuickCreateMenu>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  static const _actions = [
    (NotesQuickCreateAction.image, 'Image', Icons.image_outlined),
    (NotesQuickCreateAction.drawing, 'Drawing', Icons.brush_outlined),
    (NotesQuickCreateAction.audio, 'Audio', Icons.mic_none_rounded),
    (NotesQuickCreateAction.list, 'List', Icons.check_box_outlined),
    (NotesQuickCreateAction.text, 'Text', Icons.text_fields_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaHeight = MediaQuery.sizeOf(context).height;
    final menuHeight = mediaHeight < 520 ? mediaHeight - 124 : 396.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: 184,
      height: _expanded ? menuHeight.clamp(220.0, 396.0).toDouble() : 56,
      child: Align(
        alignment: Alignment.bottomRight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (_expanded)
              Flexible(
                child: SingleChildScrollView(
                  reverse: true,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final (action, label, icon) in _actions) ...[
                          _buildActionButton(
                            theme: theme,
                            action: action,
                            label: label,
                            icon: icon,
                          ),
                          const SizedBox(height: 9),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            FloatingActionButton(
              key: const ValueKey('notes-add-note-fab'),
              tooltip: _expanded ? 'Close quick create' : 'Create note',
              onPressed: () => setState(() => _expanded = !_expanded),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) => RotationTransition(
                  turns: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  _expanded ? Icons.close_rounded : Icons.add_rounded,
                  key: ValueKey(_expanded),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required ThemeData theme,
    required NotesQuickCreateAction action,
    required String label,
    required IconData icon,
  }) {
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final background = isDark ? colors.onSurface : colors.surfaceContainerHigh;
    final foreground = isDark ? colors.surface : colors.onSurface;

    return Material(
      color: background,
      elevation: 3,
      shadowColor: colors.shadow.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        key: ValueKey('notes-quick-create-${action.name}'),
        borderRadius: BorderRadius.circular(28),
        onTap: () {
          setState(() => _expanded = false);
          widget.onAction(action);
        },
        child: SizedBox(
          width: 148,
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
