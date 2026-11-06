import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_design_tokens.dart';
import '../models/note_workspace_models.dart';
import '../theme/notebook_colors.dart';

class NotebookSelector extends StatefulWidget {
  const NotebookSelector({
    super.key,
    required this.notebooks,
    required this.selectedNotebookId,
    required this.onSelected,
    required this.onCreateNotebook,
    required this.onNotebookOptions,
  });

  final List<Notebook> notebooks;
  final String? selectedNotebookId;
  final ValueChanged<String?> onSelected;
  final VoidCallback onCreateNotebook;
  final ValueChanged<Notebook> onNotebookOptions;

  @override
  State<NotebookSelector> createState() => _NotebookSelectorState();
}

class _NotebookSelectorState extends State<NotebookSelector> {
  final GlobalKey _selectorKey = GlobalKey();
  OverlayEntry? _menuEntry;
  Timer? _dismissTimer;
  bool _isClosing = false;

  bool get _isOpen => _menuEntry != null;

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _menuEntry?.remove();
    _menuEntry?.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (_isOpen) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    final selectorContext = _selectorKey.currentContext;
    final selectorObject = selectorContext?.findRenderObject();
    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayObject = overlay.context.findRenderObject();
    if (selectorObject is! RenderBox ||
        overlayObject is! RenderBox ||
        !selectorObject.hasSize ||
        !overlayObject.hasSize) {
      return;
    }

    final selectorTopLeft = selectorObject.localToGlobal(
      Offset.zero,
      ancestor: overlayObject,
    );
    final overlaySize = overlayObject.size;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final bottomLimit = overlaySize.height - viewInsets.bottom - 8;
    final availableBelow =
        bottomLimit - selectorTopLeft.dy - selectorObject.size.height - 8;
    final availableAbove = selectorTopLeft.dy - 8;
    final openBelow = availableBelow >= 190 || availableBelow >= availableAbove;
    final availableHeight = math.max(
      0.0,
      openBelow ? availableBelow : availableAbove,
    );
    final menuHeight = math.min(360.0, availableHeight);
    final availableMenuWidth = math.max(0.0, overlaySize.width - 24);
    final menuWidth = _menuWidthForContent(context, availableMenuWidth);
    final left = selectorTopLeft.dx
        .clamp(12.0, math.max(12.0, overlaySize.width - menuWidth - 12))
        .toDouble();
    final top = openBelow
        ? selectorTopLeft.dy + selectorObject.size.height + 8
        : math.max(8.0, selectorTopLeft.dy - menuHeight - 8);
    _isClosing = false;

    _menuEntry = OverlayEntry(
      builder: (context) => Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            label: 'Dismiss notebook menu',
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeMenu,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: menuWidth,
            height: menuHeight,
            child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.escape): _closeMenu,
              },
              child: Focus(
                autofocus: true,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: _isClosing ? 1 : 0,
                    end: _isClosing ? 0 : 1,
                  ),
                  duration: AppMotion.resolve(context, AppMotion.interaction),
                  curve: AppMotion.enter,
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, -5 * (1 - value)),
                      child: child,
                    ),
                  ),
                  child: _NotebookMenu(
                    notebooks: widget.notebooks,
                    selectedNotebookId: widget.selectedNotebookId,
                    onSelected: _selectNotebook,
                    onCreateNotebook: _createNotebook,
                    onNotebookOptions: _showNotebookOptions,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_menuEntry!);
    if (mounted) {
      setState(() {});
    }
  }

  double _menuWidthForContent(BuildContext context, double maximumWidth) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final textDirection = Directionality.of(context);

    double textWidth(String text, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: textDirection,
        textScaler: mediaQuery.textScaler,
      )..layout();
      return painter.width;
    }

    final itemLabelStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final countStyle = theme.textTheme.labelSmall;
    var requiredWidth =
        90 +
        textWidth('All', itemLabelStyle) +
        textWidth(
          '${widget.notebooks.fold<int>(0, (total, notebook) => total + notebook.noteCount)}',
          countStyle,
        );

    for (final notebook in widget.notebooks) {
      final notebookWidth =
          130 +
          textWidth(notebook.name, itemLabelStyle) +
          textWidth('${notebook.noteCount}', countStyle);
      requiredWidth = math.max(requiredWidth, notebookWidth);
    }

    final createButtonLabelStyle =
        TextButtonTheme.of(context).style?.textStyle?.resolve({}) ??
        theme.textTheme.labelLarge;
    final createButtonWidth =
        66 + textWidth('New notebook', createButtonLabelStyle);
    requiredWidth = math.max(requiredWidth, createButtonWidth);

    return math.min(requiredWidth + 2, maximumWidth).toDouble();
  }

  void _closeMenu({VoidCallback? afterClose}) {
    final entry = _menuEntry;
    if (entry == null) {
      afterClose?.call();
      return;
    }
    if (_isClosing) {
      return;
    }

    _isClosing = true;
    setState(() {});
    entry.markNeedsBuild();
    _dismissTimer = Timer(
      AppMotion.resolve(context, AppMotion.interaction),
      () {
        if (!mounted || !identical(_menuEntry, entry)) {
          return;
        }
        entry.remove();
        entry.dispose();
        _menuEntry = null;
        _dismissTimer = null;
        setState(() {});
        afterClose?.call();
      },
    );
  }

  void _selectNotebook(String? notebookId) {
    _closeMenu();
    widget.onSelected(notebookId);
  }

  void _createNotebook() {
    _closeMenu(afterClose: widget.onCreateNotebook);
  }

  void _showNotebookOptions(Notebook notebook) {
    _closeMenu(afterClose: () => widget.onNotebookOptions(notebook));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    Notebook? selectedNotebook;
    for (final notebook in widget.notebooks) {
      if (notebook.id == widget.selectedNotebookId) {
        selectedNotebook = notebook;
        break;
      }
    }
    final label = selectedNotebook?.name ?? 'All';
    final icon = selectedNotebook == null
        ? Icons.folder_copy_outlined
        : notebookIconData(selectedNotebook.icon, selectedNotebook.iconType);
    final iconColor = selectedNotebook == null
        ? colorScheme.primary
        : notebookAccentColor(theme, selectedNotebook.colorValue);
    final noteCount =
        selectedNotebook?.noteCount ??
        widget.notebooks.fold<int>(
          0,
          (total, notebook) => total + notebook.noteCount,
        );
    return Semantics(
      button: true,
      expanded: _isOpen,
      label: '$label, ${_noteCountLabel(noteCount)}',
      child: Material(
        key: _selectorKey,
        color: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        child: InkWell(
          key: const ValueKey('notes-notebook-selector'),
          borderRadius: BorderRadius.circular(AppRadius.control),
          onTap: _toggleMenu,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.max(48.0, MediaQuery.sizeOf(context).width - 32),
              minHeight: 40,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 112;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isCompact) ...[
                        Icon(icon, size: 18, color: iconColor),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: isCompact
                            ? Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _noteCountLabel(noteCount),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        _isOpen
                                            ? Icons.keyboard_arrow_up_rounded
                                            : Icons.keyboard_arrow_down_rounded,
                                        color: colorScheme.onSurfaceVariant,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                      if (isCompact)
                        Icon(
                          _isOpen
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: colorScheme.onSurfaceVariant,
                          size: 18,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotebookMenu extends StatelessWidget {
  const _NotebookMenu({
    required this.notebooks,
    required this.selectedNotebookId,
    required this.onSelected,
    required this.onCreateNotebook,
    required this.onNotebookOptions,
  });

  final List<Notebook> notebooks;
  final String? selectedNotebookId;
  final ValueChanged<String?> onSelected;
  final VoidCallback onCreateNotebook;
  final ValueChanged<Notebook> onNotebookOptions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHigh.withValues(alpha: 1),
      elevation: 2,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.compactCard),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(
            alpha: theme.brightness == Brightness.light ? 0.72 : 0.54,
          ),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 5),
        itemCount: notebooks.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildItem(
              context,
              label: 'All',
              count: notebooks.fold<int>(
                0,
                (total, notebook) => total + notebook.noteCount,
              ),
              icon: Icons.folder_copy_outlined,
              iconColor: colorScheme.primary,
              selected: selectedNotebookId == null,
              onTap: () => onSelected(null),
              key: const ValueKey('notebook-selector-option-all'),
            );
          }
          if (index == notebooks.length + 1) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 10, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Divider(height: 1, color: colorScheme.outlineVariant),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 44,
                    width: double.infinity,
                    child: TextButton.icon(
                      key: const ValueKey('notebook-selector-create-button'),
                      onPressed: onCreateNotebook,
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('New notebook'),
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        foregroundColor: colorScheme.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final notebook = notebooks[index - 1];
          return _buildItem(
            context,
            label: notebook.name,
            count: notebook.noteCount,
            icon: notebookIconData(notebook.icon, notebook.iconType),
            iconColor: notebookAccentColor(theme, notebook.colorValue),
            selected: selectedNotebookId == notebook.id,
            onTap: () => onSelected(notebook.id),
            onOptions: () => onNotebookOptions(notebook),
            onLongPress: () => onNotebookOptions(notebook),
            key: ValueKey('notebook-selector-option-${notebook.id}'),
            optionsKey: ValueKey('notebook-selector-options-${notebook.id}'),
          );
        },
      ),
    );
  }

  Widget _buildItem(
    BuildContext context, {
    required String label,
    required int count,
    required IconData icon,
    required Color iconColor,
    required bool selected,
    required VoidCallback onTap,
    required Key key,
    VoidCallback? onOptions,
    VoidCallback? onLongPress,
    Key? optionsKey,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      label: '$label, ${_noteCountLabel(count)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Material(
          color: selected
              ? Color.alphaBlend(
                  colorScheme.primary.withValues(
                    alpha: theme.brightness == Brightness.light ? 0.1 : 0.18,
                  ),
                  colorScheme.surfaceContainerHigh,
                )
              : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(11),
            onTap: onTap,
            onLongPress: onLongPress,
            child: SizedBox(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(width: 10),
                    Icon(icon, size: 20, color: iconColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        softWrap: true,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: selected ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                    Text(
                      '$count',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (onOptions != null)
                      IconButton(
                        key: optionsKey,
                        tooltip: 'Notebook options for $label',
                        onPressed: onOptions,
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          color: colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 44,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    if (selected)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(
                          Icons.check_rounded,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                      )
                    else
                      const SizedBox(width: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _noteCountLabel(int count) => '$count ${count == 1 ? 'note' : 'notes'}';
