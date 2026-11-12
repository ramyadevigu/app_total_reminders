import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/notes/models/note_workspace_models.dart';
import '../../features/notes/services/note_workspace_storage.dart';
import '../../features/reminders/models/reminder.dart';
import '../../features/reminders/screens/add_reminder_screen.dart';
import '../../features/reminders/services/recurrence_service.dart';
import '../../features/reminders/services/reminder_storage.dart';
import '../../services/ui_sound_service.dart';
import '../../theme/app_design_tokens.dart';
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
  static const _inProgressKey = 'my_day_in_progress_v1';
  static const _orderKey = 'my_day_task_order_v1';
  static const _priorityKey = 'my_day_task_priorities_v1';
  static const _boardBreakpoint = 720.0;

  late final ReminderStorage _storage;
  late final NoteWorkspaceStorage _workspaceStorage;
  final RecurrenceService _recurrenceService = RecurrenceService();
  late Future<void> _loadFuture;
  List<Reminder> _reminders = [];
  Set<String> _completedOccurrences = {};
  Set<String> _inProgressOccurrences = {};
  Map<String, List<String>> _taskOrder = {};
  Map<String, int> _priorities = {};
  Map<String, _NoteSource> _noteSources = {};
  String? _loadError;
  bool _completedExpanded = false;
  _MyDayView _view = _MyDayView.grid;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? ReminderStorage();
    _workspaceStorage = widget.workspaceStorage ?? NoteWorkspaceStorage();
    _loadFuture = _load();
    UiSoundService.instance.preload();
  }

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final completed = _readStringSet(preferences.getString(_completionKey));
      final inProgress = _readStringSet(preferences.getString(_inProgressKey));
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
        _inProgressOccurrences = inProgress;
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

  Set<String> _readStringSet(String? raw) {
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    return decoded is List ? decoded.whereType<String>().toSet() : {};
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

  DateTime get _today {
    final now = widget.clock();
    return DateTime(now.year, now.month, now.day);
  }

  String _dayKey(DateTime day) => '${day.year}-${day.month}-${day.day}';

  String _occurrenceKey(Reminder reminder, DateTime day) =>
      '${_dayKey(day)}:${reminder.id}';

  DateTime _localDate(DateTime date) => date.isUtc ? date.toLocal() : date;

  DateTime _dueDay(Reminder reminder) {
    final scheduledAt = _localDate(reminder.dateTime);
    return DateTime(scheduledAt.year, scheduledAt.month, scheduledAt.day);
  }

  /// Overdue one-time tasks stay on their due day; everything else is today's.
  DateTime _homeDay(Reminder reminder, DateTime today) {
    final dueDay = _dueDay(reminder);
    final isOverdue =
        reminder.recurrenceRule.type == RecurrenceType.none &&
        dueDay.isBefore(today);
    return isOverdue ? dueDay : today;
  }

  bool _occursOn(Reminder reminder, DateTime day) {
    if (reminder.recurrenceRule.type == RecurrenceType.none) {
      return day == _dueDay(reminder);
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

  _TaskStatus _statusFor(Reminder reminder, DateTime day) {
    final key = _occurrenceKey(reminder, day);
    if (_completedOccurrences.contains(key)) return _TaskStatus.completed;
    if (_inProgressOccurrences.contains(key)) return _TaskStatus.inProgress;
    return _TaskStatus.notStarted;
  }

  _DayPlan _buildPlan(DateTime today) {
    final order = _taskOrder[_dayKey(today)] ?? const <String>[];
    final positions = {for (var i = 0; i < order.length; i++) order[i]: i};
    final planned = _reminders
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
    planned.sort((first, second) {
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

    final overdue = <Reminder>[];
    final completedOverdue = <Reminder>[];
    for (final reminder in _reminders) {
      if (!reminder.enabled ||
          reminder.recurrenceRule.type != RecurrenceType.none) {
        continue;
      }
      final dueDay = _dueDay(reminder);
      if (!dueDay.isBefore(today)) continue;
      final done = _completedOccurrences.contains(
        _occurrenceKey(reminder, dueDay),
      );
      if (reminder.isCompleted) {
        if (done) completedOverdue.add(reminder);
      } else if (!done) {
        overdue.add(reminder);
      }
    }
    overdue.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    completedOverdue.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return _DayPlan(
      planned: planned,
      overdue: overdue,
      completedOverdue: completedOverdue,
    );
  }

  Future<void> _setTaskStatus(
    Reminder reminder,
    DateTime day,
    _TaskStatus status,
  ) async {
    final key = _occurrenceKey(reminder, day);
    final completedKeys = Set<String>.of(_completedOccurrences)..remove(key);
    final inProgressKeys = Set<String>.of(_inProgressOccurrences)..remove(key);
    if (status == _TaskStatus.inProgress) inProgressKeys.add(key);
    if (status == _TaskStatus.completed) completedKeys.add(key);
    final isDone = status == _TaskStatus.completed;

    try {
      if (reminder.recurrenceRule.type == RecurrenceType.none &&
          reminder.isCompleted != isDone) {
        await _storage.updateReminder(reminder.copyWith(isCompleted: isDone));
      }
      await _saveStringSet(_completionKey, completedKeys);
      await _saveStringSet(_inProgressKey, inProgressKeys);
      if (!mounted) return;
      setState(() {
        _completedOccurrences = completedKeys;
        _inProgressOccurrences = inProgressKeys;
        if (isDone) _completedExpanded = true;
      });
      UiSoundService.instance.play();
      await _load();
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'My Day task status',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task status could not be saved.')),
        );
      }
    }
  }

  Future<void> _saveStringSet(String key, Set<String> values) async {
    final saved = await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode(values.toList()),
    );
    if (!saved) throw StateError('Unable to save $key.');
  }

  Future<void> _openTaskEditor({Reminder? reminder}) async {
    final today = _today;
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
      UiSoundService.instance.play();
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
      UiSoundService.instance.play();
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
      UiSoundService.instance.play();
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
      if (mounted) {
        setState(() => _priorities = updated);
        UiSoundService.instance.play();
      }
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
                  const SizedBox(height: AppSpacing.sm),
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
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xxl,
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: _buildContent(context, now),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, DateTime now) {
    final today = _today;
    final plan = _buildPlan(today);
    final total = plan.planned.length;
    final planned = [
      for (final reminder in plan.planned)
        (reminder: reminder, status: _statusFor(reminder, today)),
    ];
    final done = planned
        .where((item) => item.status == _TaskStatus.completed)
        .length;
    final active = [
      for (final item in planned)
        if (item.status != _TaskStatus.completed) item.reminder,
    ];
    final completedTasks = [
      for (final item in planned)
        if (item.status == _TaskStatus.completed) item.reminder,
      ...plan.completedOverdue,
    ];
    final hasAnyTasks =
        total > 0 || plan.overdue.isNotEmpty || plan.completedOverdue.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, now: now, total: total, done: done),
        const SizedBox(height: AppSpacing.lg),
        if (hasAnyTasks) ...[
          _buildViewToggle(),
          const SizedBox(height: AppSpacing.lg),
          if (_view == _MyDayView.grid)
            _buildGrid(
              context,
              today: today,
              plan: plan,
              active: active,
              completedTasks: completedTasks,
              totalPlanned: total,
            )
          else
            _buildBoard(
              context,
              today: today,
              planned: plan.planned,
            ),
          const SizedBox(height: AppSpacing.lg),
          _buildAddTaskButton(context),
        ] else
          _buildEmptyState(context),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required DateTime now,
    required int total,
    required int done,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final subtitle = total == 0
        ? "Let's plan your day."
        : done == total
        ? 'Nice work today!'
        : 'Stay focused and make today count.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MaterialLocalizations.of(context).formatFullDate(now),
          style: theme.textTheme.labelLarge?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          _greeting(now.hour),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        if (total > 0) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            '$done out of $total ${total == 1 ? 'task' : 'tasks'} completed',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: LinearProgressIndicator(
              value: done / total,
              minHeight: 6,
              color: colors.primary,
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ),
        ],
      ],
    );
  }

  String _greeting(int hour) {
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildViewToggle() {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<_MyDayView>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: _MyDayView.grid,
            icon: Icon(Icons.view_list_rounded),
            label: Text('Grid'),
          ),
          ButtonSegment(
            value: _MyDayView.board,
            icon: Icon(Icons.view_kanban_outlined),
            label: Text('Board'),
          ),
        ],
        selected: {_view},
        onSelectionChanged: (selection) {
          UiSoundService.instance.play();
          setState(() => _view = selection.first);
        },
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context, {
    required DateTime today,
    required _DayPlan plan,
    required List<Reminder> active,
    required List<Reminder> completedTasks,
    required int totalPlanned,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading(context, 'Today'),
        const SizedBox(height: AppSpacing.xs),
        if (active.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              totalPlanned == 0
                  ? 'Nothing is planned for today.'
                  : 'All of today’s tasks are done.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: active.length,
            onReorderItem: (oldIndex, newIndex) {
              final reordered = List<Reminder>.of(active);
              final task = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, task);
              _saveOrder(today, reordered);
            },
            itemBuilder: (context, index) => _buildGridRow(
              context,
              active[index],
              today,
              reorderIndex: index,
            ),
          ),
        if (plan.overdue.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          _buildSectionHeading(context, 'Overdue'),
          const SizedBox(height: AppSpacing.xs),
          for (final reminder in plan.overdue)
            _buildGridRow(
              context,
              reminder,
              _dueDay(reminder),
              isOverdue: true,
            ),
        ],
        if (completedTasks.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.control),
            onTap: () => setState(() => _completedExpanded = !_completedExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.xs,
                horizontal: AppSpacing.xxs,
              ),
              child: Row(
                children: [
                  Icon(
                    _completedExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _buildSectionHeading(
                    context,
                    'Completed (${completedTasks.length})',
                  ),
                ],
              ),
            ),
          ),
          if (_completedExpanded)
            for (final reminder in completedTasks)
              _buildGridRow(context, reminder, _homeDay(reminder, today)),
        ],
      ],
    );
  }

  Widget _buildGridRow(
    BuildContext context,
    Reminder reminder,
    DateTime day, {
    int? reorderIndex,
    bool isOverdue = false,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = _statusFor(reminder, day);
    final completed = status == _TaskStatus.completed;
    final scheduledAt = _localDate(reminder.dateTime);
    final noteSource = _noteSources[reminder.id];
    final priority = _priorities[reminder.id];

    return DecoratedBox(
      key: ValueKey('my-day-task-${reminder.id}-${_dayKey(day)}'),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Checkbox(
            key: ValueKey('my-day-checkbox-${reminder.id}-${_dayKey(day)}'),
            value: completed,
            onChanged: (checked) => _setTaskStatus(
              reminder,
              day,
              checked == true ? _TaskStatus.completed : _TaskStatus.notStarted,
            ),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.control),
              onTap: () => _openTaskEditor(reminder: reminder),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: completed
                            ? colors.onSurfaceVariant
                            : colors.onSurface,
                        decoration: completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          MaterialLocalizations.of(context).formatTimeOfDay(
                            TimeOfDay.fromDateTime(scheduledAt),
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        _buildStatusLabel(context, status),
                        if (isOverdue)
                          Text(
                            MaterialLocalizations.of(
                              context,
                            ).formatMediumDate(scheduledAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.error,
                            ),
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
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.primary,
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
          if (priority != null) _buildPriorityFlag(priority, colors),
          _buildTaskMenu(
            context,
            reminder,
            day,
            status,
            isOverdue: isOverdue,
          ),
          if (reorderIndex != null)
            ReorderableDragStartListener(
              index: reorderIndex,
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: Icon(
                  Icons.drag_handle_rounded,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBoard(
    BuildContext context, {
    required DateTime today,
    required List<Reminder> planned,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = [
          for (final status in _TaskStatus.values)
            _buildBoardColumn(
              context,
              status,
              today,
              [
                for (final reminder in planned)
                  if (_statusFor(reminder, today) == status) reminder,
              ],
            ),
        ];
        if (constraints.maxWidth >= _boardBreakpoint) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final column in columns)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxs,
                      ),
                      child: column,
                    ),
                  ),
              ],
            ),
          );
        }
        return Column(
          children: [
            for (final column in columns)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: column,
              ),
          ],
        );
      },
    );
  }

  Widget _buildBoardColumn(
    BuildContext context,
    _TaskStatus status,
    DateTime today,
    List<Reminder> tasks,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DragTarget<_BoardDrag>(
      onWillAcceptWithDetails: (details) => details.data.status != status,
      onAcceptWithDetails: (details) =>
          _setTaskStatus(details.data.reminder, today, status),
      builder: (context, candidates, rejected) {
        final highlighted = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: AppMotion.micro,
          curve: AppMotion.standard,
          constraints: const BoxConstraints(minHeight: 120),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: highlighted ? colors.primary : colors.outlineVariant,
              width: highlighted ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(status.icon, size: 18, color: _statusColor(status, colors)),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      status.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${tasks.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text(
                    'No tasks',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final reminder in tasks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: _buildBoardCard(context, reminder, today, status),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBoardCard(
    BuildContext context,
    Reminder reminder,
    DateTime today,
    _TaskStatus status,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final card = Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.xxs,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.compactCard),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reminder.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: status == _TaskStatus.completed
                        ? colors.onSurfaceVariant
                        : colors.onSurface,
                    decoration: status == _TaskStatus.completed
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  MaterialLocalizations.of(context).formatTimeOfDay(
                    TimeOfDay.fromDateTime(_localDate(reminder.dateTime)),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (_priorities[reminder.id] != null)
            _buildPriorityFlag(_priorities[reminder.id]!, colors),
          _buildTaskMenu(context, reminder, today, status, isOverdue: false),
        ],
      ),
    );

    return LongPressDraggable<_BoardDrag>(
      data: _BoardDrag(reminder, status),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 240,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.compactCard),
            ),
            child: Text(
              reminder.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      child: card,
    );
  }

  Widget _buildTaskMenu(
    BuildContext context,
    Reminder reminder,
    DateTime day,
    _TaskStatus status, {
    required bool isOverdue,
  }) {
    final hasPriority = _priorities[reminder.id] != null;
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Task options',
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: () => _openTaskEditor(reminder: reminder),
          child: const Text('Edit'),
        ),
        for (final target in _TaskStatus.values)
          if (target != status)
            PopupMenuItem(
              value: () => _setTaskStatus(reminder, day, target),
              child: Text('Mark as ${target.label.toLowerCase()}'),
            ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: () => _setPriority(reminder, 3),
          child: const Text('Set high priority'),
        ),
        PopupMenuItem(
          value: () => _setPriority(reminder, 2),
          child: const Text('Set normal priority'),
        ),
        PopupMenuItem(
          value: () => _setPriority(reminder, 1),
          child: const Text('Set low priority'),
        ),
        if (hasPriority)
          PopupMenuItem(
            value: () => _setPriority(reminder, null),
            child: const Text('Clear priority'),
          ),
        if (isOverdue)
          PopupMenuItem(
            value: () => _moveToToday(reminder, _today),
            child: const Text('Move to today'),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: () => _deleteReminder(reminder),
          child: const Text('Delete'),
        ),
      ],
    );
  }

  Widget _buildStatusLabel(BuildContext context, _TaskStatus status) {
    final colors = Theme.of(context).colorScheme;
    final color = _statusColor(status, colors);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(status.icon, size: 14, color: color),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          status.label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }

  Widget _buildPriorityFlag(int priority, ColorScheme colors) {
    final (label, color) = switch (priority) {
      3 => ('High priority', colors.error),
      2 => ('Normal priority', colors.tertiary),
      _ => ('Low priority', colors.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Tooltip(
        message: label,
        child: Icon(Icons.flag_rounded, size: 18, color: color),
      ),
    );
  }

  Color _statusColor(_TaskStatus status, ColorScheme colors) =>
      status == _TaskStatus.inProgress ? colors.primary : colors.onSurfaceVariant;

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.huge),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              shape: BoxShape.circle,
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Icon(
              Icons.event_available_rounded,
              size: 44,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            "Let's create your first task",
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Tasks assigned to the current day appear here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _buildAddTaskButton(context),
        ],
      ),
    );
  }

  Widget _buildAddTaskButton(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          key: const ValueKey('my-day-add-task'),
          tooltip: 'Add a task',
          onPressed: () {
            UiSoundService.instance.play();
            _openTaskEditor();
          },
          icon: const Icon(Icons.add_rounded),
          style: IconButton.styleFrom(
            fixedSize: const Size.square(48),
            shape: const CircleBorder(),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          'Add new task',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ],
    );
  }

  Widget _buildSectionHeading(BuildContext context, String title) => Text(
    title,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    ),
  );
}

enum _MyDayView { grid, board }

enum _TaskStatus {
  notStarted('Not started', Icons.radio_button_unchecked_rounded),
  inProgress('In progress', Icons.timelapse_rounded),
  completed('Completed', Icons.check_circle_rounded);

  const _TaskStatus(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _DayPlan {
  const _DayPlan({
    required this.planned,
    required this.overdue,
    required this.completedOverdue,
  });

  final List<Reminder> planned;
  final List<Reminder> overdue;
  final List<Reminder> completedOverdue;
}

class _BoardDrag {
  const _BoardDrag(this.reminder, this.status);

  final Reminder reminder;
  final _TaskStatus status;
}

class _NoteSource {
  const _NoteSource(this.notebookId, this.notebookName, this.note);

  final String notebookId;
  final String notebookName;
  final NoteEntry note;
}
