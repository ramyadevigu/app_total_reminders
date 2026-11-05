import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/notes/models/note_workspace_models.dart';
import '../../features/notes/services/note_workspace_storage.dart';
import '../../features/reminders/models/reminder.dart';
import '../../features/reminders/screens/add_reminder_screen.dart';
import '../../features/reminders/services/recurrence_service.dart';
import '../../features/reminders/services/reminder_storage.dart';
import '../../services/notification_service.dart';
import '../../widgets/app_navigation_drawer.dart';

class MyDayScreen extends StatefulWidget {
  const MyDayScreen({
    super.key,
    required this.appMenu,
    required this.navigationDrawer,
    this.storage,
    this.workspaceStorage,
    this.clock = DateTime.now,
    this.onNoteSelected,
  });

  final Widget appMenu;
  final Widget navigationDrawer;
  final ReminderStorage? storage;
  final NoteWorkspaceStorage? workspaceStorage;
  final DateTime Function() clock;
  final void Function(String notebookId, NoteEntry note)? onNoteSelected;

  @override
  State<MyDayScreen> createState() => _MyDayScreenState();
}

class _MyDayScreenState extends State<MyDayScreen> {
  static const _completionKey = 'my_day_completed_occurrences_v1';
  static const _orderKey = 'my_day_task_order_v1';
  static const _priorityKey = 'my_day_task_priorities_v1';

  late final ReminderStorage _storage;
  late final NoteWorkspaceStorage _workspaceStorage;
  final RecurrenceService _recurrenceService = RecurrenceService();
  late Future<void> _loadFuture;
  List<Reminder> _reminders = [];
  Set<String> _completedOccurrences = {};
  Map<String, List<String>> _taskOrder = {};
  Map<String, int> _priorities = {};
  Map<String, _NoteSource> _noteSources = {};
  String? _loadError;
  bool _completedExpanded = false;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? ReminderStorage();
    _workspaceStorage = widget.workspaceStorage ?? NoteWorkspaceStorage();
    _loadFuture = _load();
  }

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final rawCompleted = preferences.getString(_completionKey);
      final decodedCompleted = rawCompleted == null
          ? null
          : jsonDecode(rawCompleted);
      final completed = decodedCompleted is List
          ? decodedCompleted.whereType<String>().toSet()
          : <String>{};
      final order = _readOrder(preferences.getString(_orderKey));
      final priorities = _readPriorities(preferences.getString(_priorityKey));
      final reminders = await _storage.getReminders();
      final notebooks = await _workspaceStorage.loadWorkspace();
      final noteSources = <String, _NoteSource>{};
      for (final notebook in notebooks) {
        for (final note in notebook.notes) {
          final reminderId = note.reminderId;
          if (reminderId != null && reminderId.isNotEmpty) {
            noteSources[reminderId] = _NoteSource(
              notebook.id,
              notebook.name,
              note,
            );
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _reminders = reminders;
        _completedOccurrences = completed;
        _taskOrder = order;
        _priorities = priorities;
        _noteSources = noteSources;
        _loadError = null;
      });
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'My Day task restore',
        ),
      );
      if (mounted) setState(() => _loadError = 'My Day could not be loaded.');
    }
  }

  Map<String, List<String>> _readOrder(String? raw) {
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return {
      for (final entry in decoded.entries)
        if (entry.key is String && entry.value is List)
          entry.key as String: (entry.value as List)
              .whereType<String>()
              .toList(),
    };
  }

  Map<String, int> _readPriorities(String? raw) {
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return {
      for (final entry in decoded.entries)
        if (entry.key is String &&
            entry.value is int &&
            (entry.value as int) >= 1 &&
            (entry.value as int) <= 3)
          entry.key as String: entry.value as int,
    };
  }

  String _dayKey(DateTime day) => '${day.year}-${day.month}-${day.day}';

  String _occurrenceKey(Reminder reminder, DateTime day) =>
      '${_dayKey(day)}:${reminder.id}';

  DateTime _localDate(DateTime date) => date.isUtc ? date.toLocal() : date;

  bool _occursOn(Reminder reminder, DateTime day) {
    final start = _localDate(reminder.dateTime);
    final startDay = DateTime(start.year, start.month, start.day);
    if (reminder.recurrenceRule.type == RecurrenceType.none) {
      return day == startDay;
    }
    final previousDay = day.subtract(const Duration(microseconds: 1));
    final occurrence = _recurrenceService.nextOccurrence(
      reminder,
      after: previousDay,
    );
    if (occurrence == null) return false;
    final occurrenceDate = _localDate(occurrence);
    return occurrenceDate.year == day.year &&
        occurrenceDate.month == day.month &&
        occurrenceDate.day == day.day;
  }

  Future<void> _toggleReminder(Reminder reminder, DateTime day) async {
    final key = _occurrenceKey(reminder, day);
    final updated = Set<String>.of(_completedOccurrences);
    final completing = !updated.contains(key);
    if (completing) {
      updated.add(key);
    } else {
      updated.remove(key);
    }

    try {
      if (reminder.recurrenceRule.type == RecurrenceType.none) {
        await _storage.updateReminder(
          reminder.copyWith(isCompleted: completing),
        );
      }
      final saved = await (await SharedPreferences.getInstance()).setString(
        _completionKey,
        jsonEncode(updated.toList()),
      );
      if (!saved) throw StateError('Unable to save My Day task completion.');
      if (!mounted) return;
      setState(() {
        _completedOccurrences = updated;
        if (completing) _completedExpanded = true;
      });
      if (completing) {
        await _playCompletionSound(reminder);
      }
      await _load();
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'My Day task completion',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task completion could not be saved.')),
        );
      }
    }
  }

  Future<void> _playCompletionSound(Reminder reminder) async {
    try {
      await NotificationService.instance.previewAlarmSound(reminder.soundUri);
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'My Day completion sound',
        ),
      );
    }
  }

  Future<void> _openTaskEditor({Reminder? reminder}) async {
    final now = widget.clock();
    final today = DateTime(now.year, now.month, now.day);
    final result = await Navigator.of(context).push<Reminder>(
      MaterialPageRoute<Reminder>(
        builder: (_) => AddReminderScreen(
          reminder: reminder,
          initialDate: reminder == null ? today : null,
          navigationDrawer: widget.navigationDrawer,
        ),
      ),
    );
    if (result != null && mounted) {
      await _load();
    }
  }

  Future<void> _moveToToday(Reminder reminder, DateTime today) async {
    final scheduledAt = _localDate(reminder.dateTime);
    final updated = reminder.copyWith(
      dateTime: DateTime(
        today.year,
        today.month,
        today.day,
        scheduledAt.hour,
        scheduledAt.minute,
      ),
    );
    try {
      await _storage.updateReminder(updated);
      await _load();
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'My Day carry-over',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The task could not be moved to today.'),
          ),
        );
      }
    }
  }

  Future<void> _deleteReminder(Reminder reminder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('“${reminder.title}” will be removed from reminders.'),
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
    if (confirmed != true) return;
    try {
      await _storage.deleteReminder(reminder.id);
      await _load();
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'My Day task deletion',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The task could not be deleted.')),
        );
      }
    }
  }

  Future<void> _saveOrder(DateTime day, List<Reminder> tasks) async {
    final updated = Map<String, List<String>>.of(_taskOrder)
      ..[_dayKey(day)] = tasks.map((task) => task.id).toList();
    setState(() => _taskOrder = updated);
    try {
      final saved = await (await SharedPreferences.getInstance()).setString(
        _orderKey,
        jsonEncode(updated),
      );
      if (!saved) throw StateError('Unable to save My Day task order.');
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'My Day task ordering',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task order could not be saved.')),
        );
      }
    }
  }

  Future<void> _setPriority(Reminder reminder, int? priority) async {
    final updated = Map<String, int>.of(_priorities);
    if (priority == null) {
      updated.remove(reminder.id);
    } else {
      updated[reminder.id] = priority;
    }
    try {
      final saved = await (await SharedPreferences.getInstance()).setString(
        _priorityKey,
        jsonEncode(updated),
      );
      if (!saved) throw StateError('Unable to save task priority.');
      if (mounted) setState(() => _priorities = updated);
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'My Day task priority',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task priority could not be saved.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.clock();
    final today = DateTime(now.year, now.month, now.day);
    final todayTasks = _reminders
        .where(
          (reminder) =>
              reminder.enabled &&
              _occursOn(reminder, today) &&
              (!reminder.isCompleted ||
                  _completedOccurrences.contains(
                    _occurrenceKey(reminder, today),
                  )),
        )
        .toList();
    final order = _taskOrder[_dayKey(today)] ?? const <String>[];
    final positions = {for (var i = 0; i < order.length; i++) order[i]: i};
    todayTasks.sort((first, second) {
      final firstPosition = positions[first.id];
      final secondPosition = positions[second.id];
      if (firstPosition != null || secondPosition != null) {
        final comparison = (firstPosition ?? order.length).compareTo(
          secondPosition ?? order.length,
        );
        if (comparison != 0) return comparison;
      }
      return _localDate(first.dateTime).compareTo(_localDate(second.dateTime));
    });

    final overdueTasks = _reminders.where((reminder) {
      if (!reminder.enabled ||
          reminder.isCompleted ||
          reminder.recurrenceRule.type != RecurrenceType.none) {
        return false;
      }
      final scheduledAt = _localDate(reminder.dateTime);
      final dueDay = DateTime(
        scheduledAt.year,
        scheduledAt.month,
        scheduledAt.day,
      );
      return dueDay.isBefore(today) &&
          !_completedOccurrences.contains(_occurrenceKey(reminder, dueDay));
    }).toList()..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final completedTodayTasks = todayTasks
        .where(
          (reminder) =>
              _completedOccurrences.contains(_occurrenceKey(reminder, today)),
        )
        .toList();
    final completedOverdueTasks = _reminders.where((reminder) {
      if (!reminder.enabled ||
          !reminder.isCompleted ||
          reminder.recurrenceRule.type != RecurrenceType.none) {
        return false;
      }
      final scheduledAt = _localDate(reminder.dateTime);
      final dueDay = DateTime(
        scheduledAt.year,
        scheduledAt.month,
        scheduledAt.day,
      );
      return dueDay.isBefore(today) &&
          _completedOccurrences.contains(_occurrenceKey(reminder, dueDay));
    }).toList();
    final completedTasks = [...completedTodayTasks, ...completedOverdueTasks];
    final activeTasks = todayTasks
        .where(
          (reminder) =>
              !_completedOccurrences.contains(_occurrenceKey(reminder, today)),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Day'),
        leading: const AppNavigationMenuButton(),
        actions: [widget.appMenu],
      ),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_loadError != null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError!),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () => setState(() => _loadFuture = _load()),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          MaterialLocalizations.of(context).formatFullDate(now),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Text(
                              'Today',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            Text(
                              '${activeTasks.length} ${activeTasks.length == 1 ? 'task' : 'tasks'}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (activeTasks.isEmpty &&
                            overdueTasks.isEmpty &&
                            completedTasks.isEmpty)
                          _emptyState(context)
                        else ...[
                          if (activeTasks.isNotEmpty)
                            ReorderableListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              buildDefaultDragHandles: false,
                              itemCount: activeTasks.length,
                              onReorderItem: (oldIndex, newIndex) {
                                final reordered = List<Reminder>.of(
                                  activeTasks,
                                );
                                final task = reordered.removeAt(oldIndex);
                                reordered.insert(newIndex, task);
                                _saveOrder(today, reordered);
                              },
                              itemBuilder: (context, index) => _taskRow(
                                context,
                                activeTasks[index],
                                today,
                                reorderIndex: index,
                              ),
                            ),
                          if (overdueTasks.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            _sectionHeading(context, 'Overdue'),
                            const SizedBox(height: 4),
                            for (final reminder in overdueTasks)
                              _taskRow(
                                context,
                                reminder,
                                DateTime(
                                  _localDate(reminder.dateTime).year,
                                  _localDate(reminder.dateTime).month,
                                  _localDate(reminder.dateTime).day,
                                ),
                                isOverdue: true,
                              ),
                          ],
                          if (completedTasks.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => setState(
                                () => _completedExpanded = !_completedExpanded,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 4,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _completedExpanded
                                          ? Icons.expand_less_rounded
                                          : Icons.expand_more_rounded,
                                      size: 20,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    _sectionHeading(
                                      context,
                                      'Completed (${completedTasks.length})',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_completedExpanded)
                              for (final reminder in completedTasks)
                                _taskRow(
                                  context,
                                  reminder,
                                  _completedOccurrences.contains(
                                        _occurrenceKey(reminder, today),
                                      )
                                      ? today
                                      : DateUtils.dateOnly(
                                          _localDate(reminder.dateTime),
                                        ),
                                ),
                          ],
                        ],
                        const SizedBox(height: 12),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton.filledTonal(
                              key: const ValueKey('my-day-add-task'),
                              tooltip: 'Add a task',
                              onPressed: () => _openTaskEditor(),
                              icon: const Icon(Icons.add_rounded),
                              style: IconButton.styleFrom(
                                fixedSize: const Size.square(48),
                                shape: const CircleBorder(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Add a task',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "You're all caught up.",
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add a task when something comes to mind.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeading(BuildContext context, String title) => Text(
    title,
    style: Theme.of(context).textTheme.titleSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _taskRow(
    BuildContext context,
    Reminder reminder,
    DateTime day, {
    int? reorderIndex,
    bool isOverdue = false,
  }) {
    final key = _occurrenceKey(reminder, day);
    final completed = _completedOccurrences.contains(key);
    final colors = Theme.of(context).colorScheme;
    final scheduledAt = _localDate(reminder.dateTime);
    final noteSource = _noteSources[reminder.id];
    final priority = _priorities[reminder.id];

    return AnimatedContainer(
      key: ValueKey('my-day-task-${reminder.id}-${_dayKey(day)}'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: completed ? colors.surfaceContainerLow : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                key: ValueKey('my-day-checkbox-${reminder.id}-${_dayKey(day)}'),
                value: completed,
                onChanged: (_) => _toggleReminder(reminder, day),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openTaskEditor(reminder: reminder),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 180),
                          style: Theme.of(context).textTheme.bodyLarge!
                              .copyWith(
                                color: completed
                                    ? colors.onSurfaceVariant
                                    : colors.onSurface,
                                decoration: completed
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                          child: Text(
                            reminder.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 10,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              MaterialLocalizations.of(context).formatTimeOfDay(
                                TimeOfDay.fromDateTime(scheduledAt),
                              ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                            if (isOverdue)
                              Text(
                                MaterialLocalizations.of(context)
                                    .formatMediumDate(scheduledAt),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colors.error),
                              ),
                            if (noteSource != null)
                              InkWell(
                                onTap: widget.onNoteSelected == null
                                    ? null
                                    : () => widget.onNoteSelected!(
                                        noteSource.notebookId,
                                        noteSource.note,
                                      ),
                                child: Text(
                                  'Notes · ${noteSource.notebookName}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: colors.primary),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (priority != null)
                Icon(
                  Icons.flag_rounded,
                  size: 18,
                  color: switch (priority) {
                    3 => colors.error,
                    2 => colors.tertiary,
                    _ => colors.onSurfaceVariant,
                  },
                ),
              PopupMenuButton<String>(
                tooltip: 'Task options',
                onSelected: (action) {
                  switch (action) {
                    case 'edit':
                      _openTaskEditor(reminder: reminder);
                    case 'priority-high':
                      _setPriority(reminder, 3);
                    case 'priority-medium':
                      _setPriority(reminder, 2);
                    case 'priority-low':
                      _setPriority(reminder, 1);
                    case 'priority-clear':
                      _setPriority(reminder, null);
                    case 'move-today':
                      _moveToToday(
                        reminder,
                        DateTime(
                          widget.clock().year,
                          widget.clock().month,
                          widget.clock().day,
                        ),
                      );
                    case 'delete':
                      _deleteReminder(reminder);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(
                    value: 'priority-high',
                    child: Text('Set high priority'),
                  ),
                  const PopupMenuItem(
                    value: 'priority-medium',
                    child: Text('Set normal priority'),
                  ),
                  const PopupMenuItem(
                    value: 'priority-low',
                    child: Text('Set low priority'),
                  ),
                  if (priority != null)
                    const PopupMenuItem(
                      value: 'priority-clear',
                      child: Text('Clear priority'),
                    ),
                  if (isOverdue)
                    const PopupMenuItem(
                      value: 'move-today',
                      child: Text('Move to today'),
                    ),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
                icon: const Icon(Icons.more_horiz_rounded),
              ),
              if (reorderIndex != null)
                ReorderableDragStartListener(
                  index: reorderIndex,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          Divider(height: 1, indent: 56, color: colors.outlineVariant),
        ],
      ),
    );
  }
}

class _NoteSource {
  const _NoteSource(this.notebookId, this.notebookName, this.note);

  final String notebookId;
  final String notebookName;
  final NoteEntry note;
}
