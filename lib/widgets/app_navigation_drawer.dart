import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../features/notes/models/note_workspace_models.dart';
import '../features/notes/services/note_workspace_storage.dart';

enum AppNavigationDestination {
  profile,
  search,
  reminders,
  settings,
  calendar,
  myDay,
  notes,
  stopwatch,
  timer,
}

class AppNavigationMenuButton extends StatelessWidget {
  const AppNavigationMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => IconButton(
        key: const ValueKey('global-navigation-button'),
        tooltip: 'Open navigation menu',
        onPressed: () => AppNavigationDrawerHost.openDrawer(context),
        icon: const Icon(Icons.menu_rounded),
      ),
    );
  }
}

class AppNavigationDrawerHost extends InheritedWidget {
  const AppNavigationDrawerHost({
    super.key,
    required this.onOpenDrawer,
    required super.child,
  });

  final VoidCallback onOpenDrawer;

  static void openDrawer(BuildContext context) {
    final host = context
        .getInheritedWidgetOfExactType<AppNavigationDrawerHost>();
    if (host != null) {
      host.onOpenDrawer();
      return;
    }
    Scaffold.maybeOf(context)?.openDrawer();
  }

  @override
  bool updateShouldNotify(AppNavigationDrawerHost oldWidget) =>
      onOpenDrawer != oldWidget.onOpenDrawer;
}

class AppNavigationDrawer extends StatefulWidget {
  const AppNavigationDrawer({
    super.key,
    required this.selectedDestination,
    required this.onDestinationSelected,
    required this.onNotebookSelected,
    required this.onNoteSelected,
    this.workspaceStorage,
    this.workspaceChanges,
  });

  final AppNavigationDestination selectedDestination;
  final ValueChanged<AppNavigationDestination> onDestinationSelected;
  final ValueChanged<String> onNotebookSelected;
  final void Function(String notebookId, NoteEntry note) onNoteSelected;
  final NoteWorkspaceStorage? workspaceStorage;
  final ValueListenable<int>? workspaceChanges;

  @override
  State<AppNavigationDrawer> createState() => _AppNavigationDrawerState();
}

class _AppNavigationDrawerState extends State<AppNavigationDrawer> {
  late Future<List<Notebook>> _notebooksFuture;
  final Set<String> _expandedNotebooks = {};

  @override
  void initState() {
    super.initState();
    _notebooksFuture = _loadNotebooks();
    widget.workspaceChanges?.addListener(_reloadNotebooks);
  }

  @override
  void didUpdateWidget(covariant AppNavigationDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceChanges != widget.workspaceChanges) {
      oldWidget.workspaceChanges?.removeListener(_reloadNotebooks);
      widget.workspaceChanges?.addListener(_reloadNotebooks);
    }
  }

  @override
  void dispose() {
    widget.workspaceChanges?.removeListener(_reloadNotebooks);
    super.dispose();
  }

  void _reloadNotebooks() {
    setState(() => _notebooksFuture = _loadNotebooks());
  }

  Future<List<Notebook>> _loadNotebooks() {
    return (widget.workspaceStorage ?? NoteWorkspaceStorage()).loadWorkspace();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final width = math.min(MediaQuery.sizeOf(context).width * 0.86, 360.0);

    return Drawer(
      width: width,
      backgroundColor: Colors.transparent,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: ColoredBox(
            color: colors.surface.withValues(
              alpha: Theme.of(context).brightness == Brightness.light
                  ? 0.94
                  : 0.9,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: SafeArea(
                child: FutureBuilder<List<Notebook>>(
                  future: _notebooksFuture,
                  builder: (context, snapshot) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 18),
                          child: Row(
                            children: [
                              Icon(
                                Icons.event_note_rounded,
                                size: 28,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Profile',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        _destinationTile(
                          context,
                          AppNavigationDestination.profile,
                          Icons.account_circle_outlined,
                          'Profile',
                        ),
                        _destinationTile(
                          context,
                          AppNavigationDestination.search,
                          Icons.search_rounded,
                          'Search',
                        ),
                        _destinationTile(
                          context,
                          AppNavigationDestination.myDay,
                          Icons.wb_sunny_outlined,
                          'My Day',
                        ),
                        _divider(context),
                        _sectionLabel(context, 'PLANNING'),
                        _destinationTile(
                          context,
                          AppNavigationDestination.calendar,
                          Icons.calendar_month_outlined,
                          'Calendar',
                        ),
                        _divider(context),
                        _sectionLabel(context, 'NOTES'),
                        _destinationTile(
                          context,
                          AppNavigationDestination.notes,
                          Icons.sticky_note_2_outlined,
                          'Notes',
                        ),
                        if (snapshot.hasError)
                          ListTile(
                            leading: const Icon(Icons.warning_amber_rounded),
                            title: const Text('Categories unavailable'),
                            subtitle: const Text('Notes could not be loaded.'),
                          )
                        else if (snapshot.connectionState !=
                            ConnectionState.done)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          )
                        else
                          for (final notebook
                              in snapshot.data ?? const <Notebook>[])
                            _notebookTile(context, notebook),
                        _divider(context),
                        _destinationTile(
                          context,
                          AppNavigationDestination.reminders,
                          Icons.notifications_none_rounded,
                          'Alarms',
                        ),
                        _sectionLabel(context, 'TOOLS'),
                        _destinationTile(
                          context,
                          AppNavigationDestination.stopwatch,
                          Icons.av_timer_outlined,
                          'Stopwatch',
                        ),
                        _destinationTile(
                          context,
                          AppNavigationDestination.timer,
                          Icons.hourglass_bottom_outlined,
                          'Timer',
                        ),
                        _divider(context),
                        _destinationTile(
                          context,
                          AppNavigationDestination.settings,
                          Icons.settings_outlined,
                          'Settings',
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _notebookTile(BuildContext context, Notebook notebook) {
    final expanded = _expandedNotebooks.contains(notebook.id);
    return Column(
      children: [
        ListTile(
          key: ValueKey('navigation-notebook-${notebook.id}'),
          dense: true,
          contentPadding: const EdgeInsets.only(left: 16, right: 8),
          leading: Icon(
            expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
            size: 21,
          ),
          title: Text(
            notebook.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            tooltip: expanded ? 'Collapse category' : 'Expand category',
            onPressed: () {
              setState(() {
                if (expanded) {
                  _expandedNotebooks.remove(notebook.id);
                } else {
                  _expandedNotebooks.add(notebook.id);
                }
              });
            },
            icon: Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            ),
          ),
          onTap: () {
            Scaffold.of(context).closeDrawer();
            widget.onNotebookSelected(notebook.id);
          },
        ),
        if (expanded)
          for (final note in notebook.notes)
            ListTile(
              key: ValueKey('navigation-note-${note.id}'),
              dense: true,
              contentPadding: const EdgeInsets.only(left: 52, right: 12),
              leading: const Icon(Icons.description_outlined, size: 18),
              title: Text(
                note.title.trim().isEmpty ? 'Untitled' : note.title.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              onTap: () {
                Scaffold.of(context).closeDrawer();
                widget.onNoteSelected(notebook.id, note);
              },
            ),
      ],
    );
  }

  Widget _destinationTile(
    BuildContext context,
    AppNavigationDestination destination,
    IconData icon,
    String label,
  ) {
    final selected = widget.selectedDestination == destination;
    return ListTile(
      key: ValueKey('navigation-${destination.name}'),
      dense: true,
      selected: selected,
      selectedColor: Theme.of(context).colorScheme.primary,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer
          .withValues(alpha: 0.56),
      leading: Icon(icon),
      title: Text(label),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onTap: () {
        Scaffold.of(context).closeDrawer();
        if (destination != widget.selectedDestination) {
          widget.onDestinationSelected(destination);
        }
      },
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      child: Divider(
        height: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}
