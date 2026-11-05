import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'models/calendar_view_mode.dart';
import 'widgets/calendar_view_selector.dart';
import '../reminders/models/reminder.dart';
import '../reminders/screens/add_reminder_screen.dart';
import '../reminders/services/reminder_storage.dart';
import 'services/calendar_service.dart';
import 'theme/calendar_colors.dart';
import '../../theme/app_design_tokens.dart';
import '../../theme/premium_surface.dart';
import '../../widgets/app_navigation_drawer.dart';

const _calendarMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _calendarShortMonthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sept',
  'Oct',
  'Nov',
  'Dec',
];

const _calendarShortWeekdayNames = [
  'Sun',
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
];

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    this.storage,
    this.clock = DateTime.now,
    this.viewMode = CalendarViewMode.month,
    this.onViewModeChanged,
    this.appMenu,
    this.navigationDrawer,
    this.useInternalNavigationDrawer = true,
  });

  final ReminderStorage? storage;
  final DateTime Function() clock;
  final CalendarViewMode viewMode;
  final ValueChanged<CalendarViewMode>? onViewModeChanged;
  final Widget? appMenu;
  final Widget? navigationDrawer;
  final bool useInternalNavigationDrawer;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with SingleTickerProviderStateMixin {
  late final ReminderStorage _storage;
  final CalendarService _calendarService = CalendarService();

  late DateTime _selectedDate;
  late DateTime _displayedMonth;
  late DateTime _today;
  late CalendarViewMode _activeViewMode;
  List<Reminder> _reminders = [];
  Map<DateTime, List<CalendarOccurrence>> _occurrencesByDate = {};
  List<CalendarOccurrence> _upcomingOccurrences = [];
  int _monthTransitionDirection = 1;
  late final AnimationController _monthSettleController;
  Animation<Offset>? _monthSettleAnimation;
  Offset _monthDragOffset = Offset.zero;
  Offset _monthGestureDelta = Offset.zero;
  Offset? _monthPointerPosition;
  int? _monthPointerId;
  VelocityTracker? _monthVelocityTracker;
  Axis? _monthDragAxis;
  int? _pendingMonthChange;
  double _weekSwipeDelta = 0;
  bool _isMonthTransitioning = false;
  bool _skipNextMonthSwitcherTransition = false;
  bool _isLoading = true;
  bool _hasLoadError = false;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? ReminderStorage();
    final today = _dateOnly(widget.clock());
    _today = today;
    _activeViewMode = widget.viewMode;
    _selectedDate = today;
    _displayedMonth = DateTime(today.year, today.month);
    _monthSettleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addStatusListener(_handleMonthSettleStatus);
    _loadReminders();
  }

  @override
  void dispose() {
    _monthSettleController.dispose();
    super.dispose();
  }

  void _handleMonthSettleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) {
      return;
    }
    final monthChange = _pendingMonthChange;
    setState(() {
      if (monthChange != null) {
        _skipNextMonthSwitcherTransition = true;
        _applyMonthChange(monthChange);
      }
      _monthDragOffset = Offset.zero;
      _monthGestureDelta = Offset.zero;
      _monthDragAxis = null;
      _pendingMonthChange = null;
      _monthSettleAnimation = null;
      _isMonthTransitioning = false;
    });
    if (monthChange != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _skipNextMonthSwitcherTransition = false);
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewMode != widget.viewMode) {
      _activeViewMode = widget.viewMode;
      _refreshVisibleOccurrences();
    }
  }

  void _selectViewMode(CalendarViewMode mode) {
    if (_activeViewMode == mode) {
      return;
    }
    setState(() {
      _activeViewMode = mode;
      _refreshVisibleOccurrences();
      if (mode == CalendarViewMode.list) {
        _refreshUpcomingOccurrences();
      }
    });
    widget.onViewModeChanged?.call(mode);
  }

  Future<void> _loadReminders({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _hasLoadError = false;
      });
    }

    try {
      final reminders = await _storage.getReminders();
      if (!mounted) {
        return;
      }
      setState(() {
        _reminders = reminders;
        _hasLoadError = false;
        _isLoading = false;
        _refreshVisibleOccurrences();
        _refreshUpcomingOccurrences();
      });
    } on Exception {
      if (!mounted) {
        return;
      }
      setState(() {
        _hasLoadError = true;
        _isLoading = false;
      });
    }
  }

  void _refreshVisibleOccurrences() {
    final firstOfMonth = DateTime(_displayedMonth.year, _displayedMonth.month);
    final leadingDays = firstOfMonth.weekday % DateTime.daysPerWeek;
    final firstGridDate = firstOfMonth.subtract(Duration(days: leadingDays));
    final monthEndExclusive = firstGridDate.add(
      Duration(days: _monthGridCellCount()),
    );
    final previewStart = _weekStart(_selectedDate)
        .subtract(const Duration(days: 7));
    final previewEndExclusive = previewStart.add(const Duration(days: 14));
    var start = previewStart.isBefore(firstGridDate)
        ? previewStart
        : firstGridDate;
    var endExclusive = previewEndExclusive.isAfter(monthEndExclusive)
        ? previewEndExclusive
        : monthEndExclusive;
    switch (_activeViewMode) {
      case CalendarViewMode.year:
        start = DateTime(_displayedMonth.year);
        endExclusive = DateTime(_displayedMonth.year + 1);
      case CalendarViewMode.week:
        start = _weekStart(_selectedDate);
        endExclusive = start.add(const Duration(days: 7));
      case CalendarViewMode.threeDay:
        start = _selectedDate.subtract(const Duration(days: 1));
        endExclusive = _selectedDate.add(const Duration(days: 2));
      case CalendarViewMode.day:
        start = _selectedDate;
        endExclusive = _selectedDate.add(const Duration(days: 1));
      case CalendarViewMode.list:
      case CalendarViewMode.month:
        break;
    }
    _occurrencesByDate = _calendarService.occurrencesBetween(
      _reminders,
      start: start,
      endExclusive: endExclusive,
    );
  }

  void _refreshUpcomingOccurrences() {
    final now = widget.clock();
    final countdownStart = _dateOnly(now);
    final countdownOccurrences = _calendarService.occurrencesBetween(
      _reminders,
      start: countdownStart,
      endExclusive: countdownStart.add(const Duration(days: 31)),
    );
    _upcomingOccurrences =
        countdownOccurrences.values
            .expand((occurrences) => occurrences)
            .where(
              (occurrence) =>
                  occurrence.dateTime.isAfter(now) &&
                  occurrence.reminder.recurrenceRule.type !=
                      RecurrenceType.daily,
            )
            .toList()
          ..sort((first, second) => first.dateTime.compareTo(second.dateTime));
  }

  void _changeMonth(int offset) {
    setState(() => _applyMonthChange(offset));
  }

  void _applyMonthChange(int offset) {
    final nextMonth = DateTime(
      _displayedMonth.year,
      _displayedMonth.month + offset,
    );
    final lastDay = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
    _monthTransitionDirection = offset.sign;
    _displayedMonth = nextMonth;
    _selectedDate = DateTime(
      nextMonth.year,
      nextMonth.month,
      _selectedDate.day.clamp(1, lastDay),
    );
    _refreshVisibleOccurrences();
  }

  void _startMonthSwipe(PointerDownEvent event) {
    if (_isMonthTransitioning) {
      return;
    }
    _monthSettleController.stop();
    _monthSettleAnimation = null;
    _monthDragOffset = Offset.zero;
    _monthGestureDelta = Offset.zero;
    _monthDragAxis = null;
    _monthPointerPosition = event.position;
    _monthPointerId = event.pointer;
    _monthVelocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _updateMonthSwipe(PointerMoveEvent event) {
    if (_isMonthTransitioning ||
        event.pointer != _monthPointerId ||
        _monthPointerPosition == null) {
      return;
    }
    final delta = event.position - _monthPointerPosition!;
    _monthPointerPosition = event.position;
    _monthGestureDelta += delta;
    _monthVelocityTracker?.addPosition(event.timeStamp, event.position);
    if (_monthDragAxis == null && _monthGestureDelta.distance >= 12) {
      _monthDragAxis =
          _monthGestureDelta.dx.abs() >= _monthGestureDelta.dy.abs()
          ? Axis.horizontal
          : Axis.vertical;
    }
    final axis = _monthDragAxis;
    if (axis == null) {
      return;
    }
    setState(() {
      _monthDragOffset = axis == Axis.horizontal
          ? Offset(_monthGestureDelta.dx, 0)
          : Offset(0, _monthGestureDelta.dy);
    });
  }

  void _endMonthSwipe(Offset velocity, Size size) {
    if (_isMonthTransitioning) {
      return;
    }
    final axis = _monthDragAxis;
    if (axis == null) {
      _monthGestureDelta = Offset.zero;
      return;
    }

    final displacement = axis == Axis.horizontal
        ? _monthDragOffset.dx
        : _monthDragOffset.dy;
    final primaryVelocity = axis == Axis.horizontal ? velocity.dx : velocity.dy;
    final extent = axis == Axis.horizontal ? size.width : size.height;
    final distanceThreshold = extent * (axis == Axis.horizontal ? 0.25 : 0.20);
    final distanceReached = displacement.abs() >= distanceThreshold;
    final velocityReached = primaryVelocity.abs() > 800;
    final shouldCommit = distanceReached || velocityReached;
    final directionValue = distanceReached ? displacement : primaryVelocity;
    final monthChange = shouldCommit ? (directionValue < 0 ? 1 : -1) : null;
    final settlingOffset = shouldCommit
        ? (axis == Axis.horizontal
              ? Offset(-monthChange! * size.width, 0)
              : Offset(0, -monthChange! * size.height))
        : Offset.zero;

    _isMonthTransitioning = true;
    _pendingMonthChange = monthChange;
    _monthSettleAnimation =
        Tween<Offset>(begin: _monthDragOffset, end: settlingOffset).animate(
          CurvedAnimation(
            parent: _monthSettleController,
            curve: Curves.easeOutCubic,
          ),
        );
    _monthSettleController.forward(from: 0);
  }

  void _finishMonthPointer(PointerEvent event, Size size) {
    if (event.pointer != _monthPointerId) {
      return;
    }
    final velocity = _monthVelocityTracker?.getVelocity().pixelsPerSecond;
    _monthPointerId = null;
    _monthPointerPosition = null;
    _monthVelocityTracker = null;
    _endMonthSwipe(velocity ?? Offset.zero, size);
  }

  void _cancelMonthSwipe() {
    _monthPointerId = null;
    _monthPointerPosition = null;
    _monthVelocityTracker = null;
    if (_isMonthTransitioning || _monthDragAxis == null) {
      return;
    }
    _isMonthTransitioning = true;
    _pendingMonthChange = null;
    _monthSettleAnimation =
        Tween<Offset>(begin: _monthDragOffset, end: Offset.zero).animate(
          CurvedAnimation(
            parent: _monthSettleController,
            curve: Curves.easeOutCubic,
          ),
        );
    _monthSettleController.forward(from: 0);
  }

  void _changePeriod(int offset) {
    switch (_activeViewMode) {
      case CalendarViewMode.year:
        _setYear(_displayedMonth.year + offset);
      case CalendarViewMode.week:
        _changeWeek(offset);
      case CalendarViewMode.list:
      case CalendarViewMode.month:
      case CalendarViewMode.threeDay:
      case CalendarViewMode.day:
        _changeMonth(offset);
    }
  }

  void _changeWeek(int offset) {
    final selectedDate = _selectedDate.add(Duration(days: offset * 7));
    setState(() {
      _selectedDate = selectedDate;
      _displayedMonth = DateTime(selectedDate.year, selectedDate.month);
      _today = _dateOnly(widget.clock());
      _refreshVisibleOccurrences();
    });
  }

  void _setYear(int year) {
    if (year == _displayedMonth.year) {
      return;
    }
    final lastDay = DateTime(year, _selectedDate.month + 1, 0).day;
    setState(() {
      _monthTransitionDirection = year > _displayedMonth.year ? 1 : -1;
      _displayedMonth = DateTime(year, _displayedMonth.month);
      _selectedDate = DateTime(
        year,
        _selectedDate.month,
        _selectedDate.day.clamp(1, lastDay),
      );
      _refreshVisibleOccurrences();
    });
  }

  Future<void> _pickYear() async {
    final year = await showDialog<int>(
      context: context,
      builder: (_) => _YearPickerDialog(
        selectedYear: _displayedMonth.year,
        currentYear: _today.year,
      ),
    );
    if (year == null || !mounted || year == _displayedMonth.year) {
      return;
    }
    _setYear(year);
  }

  Future<void> _pickDate() async {
    if (_activeViewMode == CalendarViewMode.year) {
      return _pickYear();
    }
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      _selectDate(date);
    }
  }

  void _selectDate(DateTime date) {
    final selectedDate = _dateOnly(date);
    setState(() {
      if (selectedDate.year != _displayedMonth.year ||
          selectedDate.month != _displayedMonth.month) {
        _monthTransitionDirection = selectedDate.isAfter(_displayedMonth)
            ? 1
            : -1;
      }
      _selectedDate = selectedDate;
      if (_selectedDate.month != _displayedMonth.month ||
          _selectedDate.year != _displayedMonth.year) {
        _displayedMonth = DateTime(_selectedDate.year, _selectedDate.month);
      }
      _refreshVisibleOccurrences();
    });
  }

  void _returnToToday() {
    final today = _dateOnly(widget.clock());
    setState(() {
      _monthTransitionDirection = today.isBefore(_displayedMonth) ? -1 : 1;
      _today = today;
      _selectedDate = today;
      _displayedMonth = DateTime(today.year, today.month);
      _refreshVisibleOccurrences();
      _refreshUpcomingOccurrences();
    });
  }

  Future<void> _openAddReminder() async {
    final reminder = await Navigator.of(context).push<Reminder>(
      MaterialPageRoute<Reminder>(
        builder: (_) => AddReminderScreen(
          storage: _storage,
          initialDate: _selectedDate,
          navigationDrawer: widget.navigationDrawer,
        ),
      ),
    );
    if (reminder != null && mounted) {
      await _loadReminders(showLoading: true);
    }
  }

  Future<void> _openEditReminder(Reminder reminder) async {
    final updatedReminder = await Navigator.of(context).push<Reminder>(
      MaterialPageRoute<Reminder>(
        builder: (_) => AddReminderScreen(
          reminder: reminder,
          storage: _storage,
          navigationDrawer: widget.navigationDrawer,
        ),
      ),
    );
    if (updatedReminder != null && mounted) {
      await _loadReminders(showLoading: true);
    }
  }

  Future<void> _deleteReminder(Reminder reminder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('Delete reminder?'),
        content: Text('Delete "${reminder.title}"? This cannot be undone.'),
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
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await _storage.deleteReminder(reminder.id);
      if (mounted) {
        await _loadReminders(showLoading: true);
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to delete the reminder.')),
        );
      }
    }
  }

  bool _isToday(DateTime date) => _sameDay(date, _today);

  bool _sameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  DateTime _dateOnly(DateTime date) {
    final localDate = date.isUtc ? date.toLocal() : date;
    return DateTime(localDate.year, localDate.month, localDate.day);
  }

  List<CalendarOccurrence> _occurrencesFor(
    DateTime date, [
    Map<DateTime, List<CalendarOccurrence>>? occurrencesByDate,
  ]) => (occurrencesByDate ?? _occurrencesByDate)[_dateOnly(date)] ?? const [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: widget.useInternalNavigationDrawer
          ? widget.navigationDrawer
          : null,
      appBar: _isLoading || _hasLoadError
          ? AppBar(
              title: const Text('Calendar'),
              leading: Builder(
                builder: (context) => IconButton(
                  key: const ValueKey('global-navigation-button'),
                  tooltip: 'Open navigation menu',
                  onPressed: () => AppNavigationDrawerHost.openDrawer(context),
                  icon: const Icon(Icons.menu_rounded),
                ),
              ),
            )
          : null,
      body: SafeArea(child: _buildBody(context)),
      floatingActionButton: FloatingActionButton(
        heroTag: 'calendar-add-reminder',
        shape: const CircleBorder(),
        onPressed: _openAddReminder,
        tooltip: 'Add reminder for selected date',
        child: const Icon(Icons.add_rounded, size: 30),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasLoadError) {
      final theme = Theme.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: theme.colorScheme.error,
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                'Unable to load calendar reminders.',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _loadReminders(showLoading: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCalendarHeader(context),
          const SizedBox(height: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.resolve(context, AppMotion.component),
              switchInCurve: AppMotion.standard,
              switchOutCurve: AppMotion.standard,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.08, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: _buildViewContent(
                context,
                key: ValueKey('calendar-view-${_activeViewMode.name}'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewContent(BuildContext context, {required Key key}) {
    return switch (_activeViewMode) {
      CalendarViewMode.list => _buildListView(context, key),
      CalendarViewMode.year => _buildYearView(context, key),
      CalendarViewMode.month => _buildMonthView(context, key),
      CalendarViewMode.week => _buildWeekView(context, key),
      CalendarViewMode.threeDay => _buildTimelineView(
        context,
        CalendarViewMode.threeDay,
        key,
      ),
      CalendarViewMode.day => _buildDayView(context, key),
    };
  }

  Widget _buildListView(BuildContext context, Key key) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final displayedMonth = DateTime(
          _displayedMonth.year,
          _displayedMonth.month,
        );
        final occurrencesByDate = _occurrencesByDate;
        final monthKey = ValueKey(
          'calendar-list-month-${displayedMonth.year}-'
          '${displayedMonth.month}',
        );
        return Column(
          key: key,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: constraints.maxHeight * 0.55,
              child: Column(
                children: [
                  _buildWeekdayHeader(context),
                  Expanded(
                    child: _buildMonthSwipeRegion(
                      context,
                      month: displayedMonth,
                      buildMonth: (month, date, isPreview) {
                        final card = _buildMonthGridCard(
                          context,
                          key: isPreview
                              ? ValueKey(
                                  'calendar-list-month-${month.year}-'
                                  '${month.month}',
                                )
                              : monthKey,
                          monthOnly: true,
                          monthContext: month,
                          selectedDateContext: date,
                          occurrencesByDateContext: occurrencesByDate,
                          exposeGridKey: !isPreview,
                        );
                        if (isPreview) {
                          return card;
                        }
                        return AnimatedSwitcher(
                          duration: _skipNextMonthSwitcherTransition
                              ? Duration.zero
                              : AppMotion.resolve(context, AppMotion.screen),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: _buildMonthTransition,
                          child: card,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Semantics(
              button: true,
              label: 'Expand Upcoming Events',
              hint: 'Open the scrollable Countdown panel',
              child: InkWell(
                key: const ValueKey('calendar-countdown-toggle'),
                onTap: _showCountdownSheet,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Upcoming Events',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Icon(
                        Icons.expand_less,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: _buildUpcomingList(
                context,
                const ValueKey('calendar-list-content'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMonthView(BuildContext context, Key key) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gridHeight = (constraints.maxHeight * 0.58)
            .clamp(280.0, 440.0)
            .toDouble();
        const selectedContentMinimumHeight = 180.0;
        final minimumContentHeight =
            26 + gridHeight + selectedContentMinimumHeight;
        final contentHeight = constraints.maxHeight < minimumContentHeight
            ? minimumContentHeight
            : constraints.maxHeight;
        return SingleChildScrollView(
          key: key,
          child: SizedBox(
            height: contentHeight,
            child: Column(
              children: [
                _buildWeekdayHeader(context),
                SizedBox(
                  height: gridHeight,
                  child: _buildMonthSwipeRegion(
                    context,
                    month: _displayedMonth,
                    buildMonth: (month, selectedDate, isPreview) {
                      final grid = _buildMonthGridCard(
                        context,
                        monthOnly: true,
                        monthContext: month,
                        selectedDateContext: selectedDate,
                        occurrencesByDateContext: _occurrencesByDate,
                        exposeGridKey: !isPreview,
                        transparentSurface: true,
                        key: ValueKey(
                          'calendar-month-${month.year}-${month.month}',
                        ),
                      );
                      if (isPreview) {
                        return grid;
                      }
                      return AnimatedSwitcher(
                        duration: _skipNextMonthSwitcherTransition
                            ? Duration.zero
                            : AppMotion.resolve(context, AppMotion.screen),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: _buildMonthTransition,
                        child: grid,
                      );
                    },
                  ),
                ),
                Expanded(child: _buildSelectedDayContent(context)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelectedDayContent(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final occurrences = _occurrencesFor(_selectedDate);
    if (occurrences.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            key: const ValueKey('calendar-empty-day'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_month_outlined,
                size: 56,
                color: colors.primary.withValues(alpha: 0.64),
              ),
              const SizedBox(height: 16),
              Text(
                'You have a free day',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Take it easy',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final countLabel =
        '${occurrences.length} ${occurrences.length == 1 ? 'reminder' : 'reminders'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          child: Text(
            countLabel,
            key: const ValueKey('calendar-selected-day-count'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            key: const ValueKey('calendar-selected-day-events'),
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 80),
            itemCount: occurrences.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              indent: 72,
              color: colors.outlineVariant.withValues(alpha: 0.4),
            ),
            itemBuilder: (context, index) {
              final occurrence = occurrences[index];
              final reminder = occurrence.reminder;
              final dark = theme.brightness == Brightness.dark;
              final reminderColor = CalendarColors.forReminder(reminder.id)
                  .foreground(dark);
              final isAlarm =
                  reminder.notificationMode ==
                  ReminderNotificationMode.alarmAndNotification;
              final time = MaterialLocalizations.of(context).formatTimeOfDay(
                TimeOfDay.fromDateTime(occurrence.dateTime),
                alwaysUse24HourFormat: true,
              );
              final recurrence =
                  reminder.recurrenceRule.type != RecurrenceType.none;

              return Semantics(
                key: ValueKey(
                  'calendar-selected-reminder-${reminder.id}-'
                  '${occurrence.dateTime.day}',
                ),
                button: true,
                label:
                    '${isAlarm ? 'Alarm' : 'Reminder'}, $time, '
                    '${reminder.title}',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _openEditReminder(reminder),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 56,
                            child: Text(
                              time,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Icon(
                            isAlarm
                                ? Icons.alarm_outlined
                                : Icons.notifications_none_outlined,
                            size: 19,
                            color: reminderColor,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              reminder.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          if (recurrence)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.repeat_rounded,
                                size: 16,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMonthSwipeRegion(
    BuildContext context, {
    required DateTime month,
    required Widget Function(
      DateTime month,
      DateTime selectedDate,
      bool isPreview,
    )
    buildMonth,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return ClipRect(
          child: Listener(
            key: const ValueKey('calendar-month-swipe-region'),
            behavior: HitTestBehavior.opaque,
            onPointerDown: _startMonthSwipe,
            onPointerMove: _updateMonthSwipe,
            onPointerUp: (event) => _finishMonthPointer(event, size),
            onPointerCancel: (_) => _cancelMonthSwipe(),
            child: AnimatedBuilder(
              animation: _monthSettleController,
              builder: (context, child) {
                final offset = _monthSettleAnimation?.value ?? _monthDragOffset;
                final axis = _monthDragAxis;
                final monthChange =
                    _pendingMonthChange ??
                    ((axis == Axis.horizontal ? offset.dx : offset.dy) < 0
                        ? 1
                        : -1);
                final neighbor = DateTime(
                  month.year,
                  month.month + monthChange,
                );
                final neighborSelectedDate = DateTime(
                  neighbor.year,
                  neighbor.month,
                  _selectedDate.day.clamp(
                    1,
                    DateTime(neighbor.year, neighbor.month + 1, 0).day,
                  ),
                );
                final currentPosition = Offset(
                  size.width == 0 ? 0 : offset.dx / size.width,
                  size.height == 0 ? 0 : offset.dy / size.height,
                );
                final neighborOffset = axis == Axis.horizontal
                    ? Offset(offset.dx + monthChange * size.width, 0)
                    : Offset(0, offset.dy + monthChange * size.height);
                final neighborPosition = Offset(
                  size.width == 0 ? 0 : neighborOffset.dx / size.width,
                  size.height == 0 ? 0 : neighborOffset.dy / size.height,
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (axis != null)
                      SlideTransition(
                        position: AlwaysStoppedAnimation(neighborPosition),
                        child: buildMonth(neighbor, neighborSelectedDate, true),
                      ),
                    SlideTransition(
                      position: AlwaysStoppedAnimation(currentPosition),
                      child: buildMonth(month, _selectedDate, false),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildMonthTransition(Widget child, Animation<double> animation) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final direction = animation.status == AnimationStatus.reverse
              ? -_monthTransitionDirection
              : _monthTransitionDirection;
          final position = AlwaysStoppedAnimation(
            Offset(direction * (1 - animation.value), 0),
          );
          return SlideTransition(position: position, child: child);
        },
      ),
    );
  }

  Widget _buildYearView(BuildContext context, Key key) {
    final year = _displayedMonth.year;
    final direction = _monthTransitionDirection;
    return AnimatedSwitcher(
      key: key,
      duration: AppMotion.resolve(context, AppMotion.component),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey('calendar-year-$year');
        final offset = Tween<Offset>(
          begin: Offset(0, incoming ? 0.08 * direction : -0.08 * direction),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: _buildYearMonths(context, year),
    );
  }

  Widget _buildYearMonths(BuildContext context, int year) {
    return LayoutBuilder(
      key: ValueKey('calendar-year-$year'),
      builder: (context, constraints) {
        const horizontalPadding = 2.0;
        const verticalPadding = 8.0;
        const bottomPadding = 64.0;
        const spacing = 8.0;
        final monthWidth =
            (constraints.maxWidth - horizontalPadding * 2 - spacing * 2) / 3;
        final monthHeight =
            (constraints.maxHeight -
                verticalPadding -
                bottomPadding -
                spacing * 3) /
            4;
        // Content fits the viewport; bouncing physics gives a spring-back
        // overscroll instead of changing the year.
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            verticalPadding,
            horizontalPadding,
            bottomPadding,
          ),
          child: RepaintBoundary(
            child: Column(
              children: [
                for (var row = 0; row < 4; row++) ...[
                  if (row > 0) const SizedBox(height: spacing),
                  SizedBox(
                    height: monthHeight,
                    child: Row(
                      children: [
                        for (var col = 0; col < 3; col++) ...[
                          if (col > 0) const SizedBox(width: spacing),
                          SizedBox(
                            width: monthWidth,
                            child: RepaintBoundary(
                              child: _buildMiniMonth(
                                context,
                                DateTime(year, row * 3 + col + 1),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniMonth(BuildContext context, DateTime month) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final firstDay = DateTime(month.year, month.month);
    final leadingDays = firstDay.weekday % DateTime.daysPerWeek;
    final dayCount = DateTime(month.year, month.month + 1, 0).day;
    final rows = (leadingDays + dayCount + 6) ~/ 7;
    final localizations = MaterialLocalizations.of(context);
    final dayStyle = (theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
      fontSize: 7,
      height: 1,
    );
    return Column(
      children: [
        SizedBox(
          height: 22,
          child: Semantics(
            button: true,
            label: 'Open ${_calendarMonthNames[month.month - 1]} ${month.year}',
            child: InkWell(
              key: ValueKey('calendar-year-month-${month.year}-${month.month}'),
              borderRadius: BorderRadius.circular(4),
              onTap: () => _openMonthFromYear(month),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _calendarShortMonthNames[month.month - 1],
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 14,
          child: Row(
            children: [
              for (final weekday in MaterialLocalizations.of(
                context,
              ).narrowWeekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      weekday,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              for (var row = 0; row < rows; row++)
                Expanded(
                  child: Row(
                    children: [
                      for (var col = 0; col < 7; col++)
                        Expanded(
                          child: _buildYearDay(
                            month,
                            row * 7 + col - leadingDays + 1,
                            dayCount,
                            dayStyle,
                            colors,
                            localizations,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildYearDay(
    DateTime month,
    int day,
    int dayCount,
    TextStyle style,
    ColorScheme colors,
    MaterialLocalizations localizations,
  ) {
    if (day < 1 || day > dayCount) {
      return const SizedBox.shrink();
    }
    final date = DateTime(month.year, month.month, day);
    final selected = _sameDay(date, _selectedDate);
    final today = _isToday(date);
    final eventCount = _occurrencesFor(date).length;
    final hasEvents = eventCount > 0;
    return Semantics(
      key: ValueKey('calendar-day-${date.year}-${date.month}-${date.day}'),
      button: true,
      selected: selected,
      label: [
        localizations.formatFullDate(date),
        if (today) 'today',
        if (selected) 'selected',
        if (hasEvents) '$eventCount reminders',
      ].join(', '),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectDate(date),
        child: Center(
          child: DecoratedBox(
            key: ValueKey(
              'calendar-day-marker-${date.year}-${date.month}-${date.day}',
            ),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? colors.primary : null,
              border: today && !selected
                  ? Border.all(color: colors.primary.withValues(alpha: 0.7))
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(1.5),
              child: Text(
                key: ValueKey(
                  'calendar-day-number-${date.year}-${date.month}-${date.day}',
                ),
                '$day',
                style: style.copyWith(
                  color: selected
                      ? colors.onPrimary
                      : hasEvents
                      ? colors.primary
                      : colors.onSurface,
                  fontWeight: selected || today || hasEvents
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openMonthFromYear(DateTime month) {
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    setState(() {
      _displayedMonth = DateTime(month.year, month.month);
      _selectedDate = DateTime(
        month.year,
        month.month,
        _selectedDate.day.clamp(1, lastDay),
      );
      _refreshVisibleOccurrences();
    });
    _selectViewMode(CalendarViewMode.month);
  }

  Widget _buildUpcomingList(BuildContext context, Key key) {
    final localizations = MaterialLocalizations.of(context);
    if (_upcomingOccurrences.isEmpty) {
      return Center(
        key: key,
        child: Text(
          'No upcoming reminders',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      key: key,
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 100),
      itemCount: _upcomingOccurrences.length,
      itemBuilder: (context, index) {
        final occurrence = _upcomingOccurrences[index];
        final reminder = occurrence.reminder;
        final color = CalendarColors.forReminder(reminder.id)
            .foreground(Theme.of(context).brightness == Brightness.dark);
        return ListTile(
          key: ValueKey('calendar-list-${reminder.id}-${occurrence.dateTime}'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: SizedBox(
            width: 48,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  localizations.formatShortDate(occurrence.dateTime),
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  MaterialLocalizations.of(context).formatTimeOfDay(
                    TimeOfDay.fromDateTime(occurrence.dateTime),
                    alwaysUse24HourFormat: true,
                  ),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          title: Text(
            reminder.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _countdownLabel(occurrence.dateTime),
                key: ValueKey(
                  'calendar-countdown-${reminder.id}-${occurrence.dateTime}',
                ),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (reminder.description case final description?
                  when description.trim().isNotEmpty)
                Text(description, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                reminder.recurrenceRule.type == RecurrenceType.none
                    ? Icons.event_outlined
                    : Icons.repeat,
                color: color,
              ),
              PopupMenuButton<String>(
                tooltip: 'More actions for ${reminder.title}',
                onSelected: (action) {
                  if (action == 'edit') {
                    _openEditReminder(reminder);
                  } else if (action == 'delete') {
                    _deleteReminder(reminder);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          onTap: () => _openEditReminder(reminder),
        );
      },
    );
  }

  String _countdownLabel(DateTime eventDateTime) {
    final now = widget.clock();
    final remaining = eventDateTime.difference(now);
    final nowDate = DateTime.utc(now.year, now.month, now.day);
    final eventDate = DateTime.utc(
      eventDateTime.year,
      eventDateTime.month,
      eventDateTime.day,
    );
    final calendarDays = eventDate.difference(nowDate).inDays;
    if (calendarDays == 1) {
      return 'Tomorrow';
    }
    if (calendarDays > 1) {
      return 'In $calendarDays days';
    }

    final minutes = (remaining.inSeconds / Duration.secondsPerMinute).ceil();
    if (minutes < Duration.minutesPerHour) {
      return minutes == 1 ? 'In 1 minute' : 'In $minutes minutes';
    }
    final hours = (minutes / Duration.minutesPerHour).ceil();
    return hours == 1 ? 'In 1 hour' : 'In $hours hours';
  }

  Widget _buildTimelineView(
    BuildContext context,
    CalendarViewMode mode,
    Key key,
  ) {
    final dates = List.generate(
      3,
      (index) => _selectedDate.add(Duration(days: index - 1)),
    );
    return Column(
      key: key,
      children: [
        _buildTimelineDateSelector(context, dates, _selectDate),
        Expanded(child: _buildMultiDayTimeline(context, mode, dates)),
      ],
    );
  }

  Widget _buildWeekView(BuildContext context, Key key) {
    final dates = List.generate(
      7,
      (index) => _weekStart(_selectedDate).add(Duration(days: index)),
    );
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final colors = theme.colorScheme;
    final weekStart = _weekStart(_selectedDate);
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('calendar-previous-week'),
              tooltip: 'Previous week',
              visualDensity: VisualDensity.compact,
              onPressed: () => _changeWeek(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${localizations.formatShortDate(dates.first)} – '
                '${localizations.formatShortDate(dates.last)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton(
              key: const ValueKey('calendar-week-today'),
              onPressed: _returnToToday,
              child: const Text('Today'),
            ),
            IconButton(
              key: const ValueKey('calendar-next-week'),
              tooltip: 'Next week',
              visualDensity: VisualDensity.compact,
              onPressed: () => _changeWeek(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        SizedBox(
          height: 66,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final date in dates)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: _buildWeekDaySummary(context, date),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: colors.outlineVariant),
        Expanded(
          child: GestureDetector(
            key: const ValueKey('calendar-week-swipe-region'),
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _weekSwipeDelta = 0,
            onHorizontalDragUpdate: (details) {
              _weekSwipeDelta += details.delta.dx;
            },
            onHorizontalDragEnd: (details) {
              final delta = _weekSwipeDelta;
              final velocity = details.primaryVelocity ?? 0;
              _weekSwipeDelta = 0;
              if (delta.abs() >= 48 || velocity.abs() >= 700) {
                _changeWeek((delta != 0 ? delta : velocity) < 0 ? 1 : -1);
              }
            },
            child: AnimatedSwitcher(
              duration: AppMotion.resolve(context, AppMotion.screen),
              child: Row(
                key: ValueKey('calendar-week-columns-$weekStart'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < dates.length; index++)
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                              color: colors.outlineVariant.withValues(
                                alpha: 0.55,
                              ),
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: ListView.builder(
                                key: ValueKey(
                                  'calendar-week-events-'
                                  '${dates[index].year}-'
                                  '${dates[index].month}-'
                                  '${dates[index].day}',
                                ),
                                padding: const EdgeInsets.fromLTRB(1, 4, 1, 32),
                                itemCount: _occurrencesFor(dates[index]).length,
                                itemBuilder: (context, eventIndex) =>
                                    _buildWeekEvent(
                                      context,
                                      _occurrencesFor(dates[index])[eventIndex],
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekDaySummary(BuildContext context, DateTime date) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final localizations = MaterialLocalizations.of(context);
    final count = _occurrencesFor(date).length;
    final selected = _sameDay(date, _selectedDate);
    final today = _isToday(date);
    return Semantics(
      key: ValueKey(
        'calendar-timeline-date-${date.year}-${date.month}-${date.day}',
      ),
      button: true,
      selected: selected,
      label: [
        localizations.formatFullDate(date),
        if (today) 'today',
        if (selected) 'selected',
        count == 0
            ? 'No reminders'
            : '$count ${count == 1 ? 'reminder' : 'reminders'}',
      ].join(', '),
      hint: 'Select date',
      child: Tooltip(
        message: count == 0
            ? 'No reminders'
            : '$count ${count == 1 ? 'reminder' : 'reminders'}',
        child: AnimatedContainer(
          key: ValueKey(
            'calendar-week-date-cell-${date.year}-${date.month}-${date.day}',
          ),
          duration: AppMotion.resolve(context, AppMotion.interaction),
          decoration: BoxDecoration(
            color: selected
                ? colors.primary
                : today
                ? colors.primaryContainer.withValues(alpha: 0.22)
                : null,
            borderRadius: BorderRadius.circular(8),
            border: today
                ? Border.all(
                    color: selected ? colors.onPrimary : colors.primary,
                    width: 1.5,
                  )
                : null,
          ),
          child: InkWell(
            onTap: () => _selectDate(date),
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 66,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _calendarShortWeekdayNames[date.weekday % 7],
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected
                          ? colors.onPrimary
                          : colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      fontSize: 9,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${date.day}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: selected
                          ? colors.onPrimary
                          : today
                          ? colors.primary
                          : colors.onSurface,
                      fontWeight: selected || today
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeekEvent(BuildContext context, CalendarOccurrence occurrence) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final colors = CalendarColors.forReminder(occurrence.reminder.id);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(occurrence.dateTime),
      alwaysUse24HourFormat: true,
    );
    final reminder = occurrence.reminder;
    final isRecurring = reminder.recurrenceRule.type != RecurrenceType.none;
    final isAlarm =
        reminder.notificationMode ==
        ReminderNotificationMode.alarmAndNotification;
    return Semantics(
      key: ValueKey(
        'calendar-week-event-${reminder.id}-${occurrence.dateTime}',
      ),
      button: true,
      label: [
        time,
        reminder.title,
        if (isRecurring) 'repeats',
        if (isAlarm) 'alarm',
      ].join(', '),
      child: Tooltip(
        message: '${reminder.title}, $time',
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Material(
            color: colors.surface(dark),
            borderRadius: BorderRadius.circular(5),
            child: InkWell(
              onTap: () => _openEditReminder(reminder),
              borderRadius: BorderRadius.circular(5),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: Border(
                    left: BorderSide(color: colors.foreground(dark), width: 2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      time,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.foreground(dark),
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      reminder.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontSize: 9,
                        height: 1.1,
                      ),
                    ),
                    if (isRecurring || isAlarm)
                      Row(
                        children: [
                          if (isRecurring)
                            Icon(
                              Icons.repeat_rounded,
                              size: 9,
                              color: colors.foreground(dark),
                            ),
                          if (isAlarm)
                            Icon(
                              Icons.alarm_outlined,
                              size: 9,
                              color: colors.foreground(dark),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayView(BuildContext context, Key key) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final occurrences = _occurrencesFor(_selectedDate);
    final count = occurrences.length;
    final countLabel = count == 0
        ? 'No reminders'
        : '$count ${count == 1 ? 'reminder' : 'reminders'}';
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizations.formatFullDate(_selectedDate),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                countLabel,
                key: const ValueKey('calendar-day-reminder-count'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: count == 0
              ? Center(
                  child: Text(
                    'No reminders',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  key: const ValueKey('calendar-day-event-list'),
                  padding: const EdgeInsets.fromLTRB(2, 0, 2, 100),
                  itemCount: occurrences.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 6),
                  itemBuilder: (context, index) =>
                      _buildDayEventListItem(context, occurrences[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildDayEventListItem(
    BuildContext context,
    CalendarOccurrence occurrence,
  ) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final reminder = occurrence.reminder;
    final eventColor = CalendarColors.forReminder(reminder.id);
    final isAlarm =
        reminder.notificationMode ==
        ReminderNotificationMode.alarmAndNotification;
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(occurrence.dateTime),
      alwaysUse24HourFormat: true,
    );
    return Semantics(
      key: ValueKey(
        'calendar-day-event-${reminder.id}-${occurrence.dateTime.toIso8601String()}',
      ),
      button: true,
      label: '${isAlarm ? 'Alarm' : 'Reminder'}, $time, ${reminder.title}',
      child: Material(
        color: eventColor.surface(dark),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _openEditReminder(reminder),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    time,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: eventColor.foreground(dark),
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  isAlarm ? Icons.alarm_rounded : Icons.event_note_outlined,
                  size: 18,
                  color: eventColor.foreground(dark),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    reminder.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (reminder.recurrenceRule.type != RecurrenceType.none)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.repeat_rounded,
                      size: 16,
                      color: eventColor.foreground(dark),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineDateSelector(
    BuildContext context,
    List<DateTime> dates,
    ValueChanged<DateTime> onDateSelected,
  ) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    return SizedBox(
      height: 64,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 48 + dates.length * 112,
          child: Row(
            children: [
              const SizedBox(width: 48),
              for (final date in dates)
                SizedBox(
                  width: 112,
                  child: Semantics(
                    key: ValueKey(
                      'calendar-timeline-date-${date.year}-${date.month}-${date.day}',
                    ),
                    button: true,
                    selected: _sameDay(date, _selectedDate),
                    label: localizations.formatFullDate(date),
                    child: InkWell(
                      onTap: () => onDateSelected(date),
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: AppMotion.resolve(
                          context,
                          AppMotion.interaction,
                        ),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: _sameDay(date, _selectedDate)
                              ? theme.colorScheme.primaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              localizations.narrowWeekdays[date.weekday % 7],
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: _sameDay(date, _selectedDate)
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '${date.day}',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: _sameDay(date, _selectedDate)
                                    ? theme.colorScheme.primary
                                    : null,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMultiDayTimeline(
    BuildContext context,
    CalendarViewMode mode,
    List<DateTime> dates,
  ) {
    return SingleChildScrollView(
      key: ValueKey('calendar-timeline-${mode.name}'),
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 48 + dates.length * 112,
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 100),
          itemCount: 24,
          itemBuilder: (context, hour) {
            final eventLists = [
              for (final date in dates) _hourOccurrences(date, hour),
            ];
            final columns = [
              for (var index = 0; index < dates.length; index++)
                _buildTimelineDateColumn(
                  context,
                  dates[index],
                  eventLists[index],
                  _isToday(dates[index]) && widget.clock().hour == hour,
                  index,
                ),
            ];
            var maximumEventCount = 0;
            for (final events in eventLists) {
              if (events.length > maximumEventCount) {
                maximumEventCount = events.length;
              }
            }
            return _buildTimelineHourRow(
              context,
              hour,
              columns,
              maximumEventCount,
            );
          },
        ),
      ),
    );
  }

  List<CalendarOccurrence> _hourOccurrences(DateTime date, int hour) =>
      _occurrencesFor(date)
          .where((occurrence) => occurrence.dateTime.hour == hour)
          .toList();

  Widget _buildTimelineHourRow(
    BuildContext context,
    int hour,
    List<Widget> columns,
    int maximumEventCount,
  ) {
    final theme = Theme.of(context);
    final rowHeight = maximumEventCount < 3
        ? 64.0
        : maximumEventCount * 24.0 + 10;
    return SizedBox(
      height: rowHeight,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: rowHeight),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 48,
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '${hour.toString().padLeft(2, '0')}:00',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            Expanded(child: Row(children: columns)),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineDateColumn(
    BuildContext context,
    DateTime date,
    List<CalendarOccurrence> occurrences,
    bool isCurrentHour,
    int index,
  ) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant.withValues(
      alpha: 0.55,
    );
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: borderColor, width: 0.7),
            left: BorderSide(color: borderColor, width: index == 0 ? 0 : 0.5),
          ),
        ),
        child: Stack(
          children: [
            if (isCurrentHour)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(height: 2, color: theme.colorScheme.primary),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 3, 0, 3),
              child: Column(
                children: [
                  for (final occurrence in occurrences)
                    _buildEventRow(context, occurrence, dense: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarHeader(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final monthTitle = _activeViewMode == CalendarViewMode.year
        ? '${_displayedMonth.year}'
        : _calendarMonthNames[_displayedMonth.month - 1];
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Builder(
            builder: (context) => IconButton(
              key: const ValueKey('global-navigation-button'),
              tooltip: 'Open navigation menu',
              visualDensity: VisualDensity.compact,
              onPressed: () => AppNavigationDrawerHost.openDrawer(context),
              icon: const Icon(Icons.menu_rounded),
            ),
          ),
          if (_activeViewMode == CalendarViewMode.week ||
              _activeViewMode == CalendarViewMode.day)
            IconButton(
              key: const ValueKey('calendar-hierarchy-back'),
              tooltip: _activeViewMode == CalendarViewMode.day
                  ? 'Back to Week'
                  : 'Back to Month',
              visualDensity: VisualDensity.compact,
              onPressed: () => _selectViewMode(
                _activeViewMode == CalendarViewMode.day
                    ? CalendarViewMode.week
                    : CalendarViewMode.month,
              ),
              icon: const Icon(Icons.chevron_left),
            ),
          Expanded(
            child: Semantics(
              button: true,
              label: _activeViewMode == CalendarViewMode.year
                  ? 'Choose year ${_displayedMonth.year}'
                  : 'Choose ${localizations.formatMonthYear(_displayedMonth)}',
              child: InkWell(
                key: const ValueKey('calendar-select-date'),
                borderRadius: BorderRadius.circular(8),
                onTap: _pickDate,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedSwitcher(
                    duration: AppMotion.resolve(context, AppMotion.interaction),
                    child: Row(
                      key: ValueKey(
                        'calendar-month-title-${_displayedMonth.year}-'
                        '${_displayedMonth.month}',
                      ),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            monthTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        if (_activeViewMode != CalendarViewMode.year) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${_displayedMonth.year}',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          CalendarViewSelector(
            selectedMode: _activeViewMode,
            onSelected: _selectViewMode,
          ),
          _buildMoreMenu(),
        ],
      ),
    );
  }

  Widget _buildMoreMenu() {
    if (widget.appMenu case final appMenu?) {
      return appMenu;
    }
    return PopupMenuButton<String>(
      tooltip: 'More calendar views',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'today') {
          _returnToToday();
        } else if (value == 'countdown') {
          _showCountdownSheet();
        } else if (value == 'previous-month') {
          _changePeriod(-1);
        } else if (value == 'next-month') {
          _changePeriod(1);
        }
      },
      itemBuilder: (context) {
        final period = switch (_activeViewMode) {
          CalendarViewMode.year => 'year',
          CalendarViewMode.week => 'week',
          _ => 'month',
        };
        return [
          const PopupMenuItem(
            value: 'countdown',
            child: ListTile(
              leading: Icon(Icons.hourglass_bottom),
              title: Text('Countdown'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuItem(
            value: 'today',
            child: ListTile(
              leading: Icon(Icons.today_outlined),
              title: Text('Go to Today'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'previous-month',
            child: ListTile(
              leading: const Icon(Icons.chevron_left),
              title: Text('Previous $period'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'next-month',
            child: ListTile(
              leading: const Icon(Icons.chevron_right),
              title: Text('Next $period'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ];
      },
    );
  }

  Widget _buildWeekdayHeader(BuildContext context, {bool compact = false}) {
    final localizations = MaterialLocalizations.of(context);
    const sundayFirstIndexes = [0, 1, 2, 3, 4, 5, 6];
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
    return SizedBox(
      height: compact ? 18 : 26,
      child: Row(
        children: [
          for (var index = 0; index < sundayFirstIndexes.length; index++)
            Expanded(
              child: Center(
                child: Text(
                  compact
                      ? localizations.narrowWeekdays[sundayFirstIndexes[index]]
                      : _calendarShortWeekdayNames[index],
                  style: style?.copyWith(fontSize: compact ? 7 : 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMonthGridCard(
    BuildContext context, {
    Key? key,
    bool monthOnly = false,
    bool compact = false,
    bool twoWeekPreview = false,
    DateTime? monthContext,
    DateTime? selectedDateContext,
    Map<DateTime, List<CalendarOccurrence>>? occurrencesByDateContext,
    bool exposeGridKey = true,
    bool transparentSurface = false,
    bool tapOpensDay = false,
  }) {
    return LayoutBuilder(
      key: key ?? ValueKey('calendar-month-grid-$monthOnly-$twoWeekPreview'),
      builder: (context, constraints) {
        final cellCount = twoWeekPreview ? 14 : _monthGridCellCount();
        final rowCount = cellCount ~/ 7;
        final surfacePadding = transparentSurface
            ? 0.0
            : compact
            ? 2.0
            : 4.0;
        final cellExtent =
            (constraints.maxHeight - surfacePadding * 2) / rowCount;
        final firstGridDate = twoWeekPreview
            ? _weekStart(_selectedDate).subtract(const Duration(days: 7))
            : _monthGridStartDate(monthContext ?? _displayedMonth);
        final grid = GridView.builder(
          key: ValueKey(
            twoWeekPreview
                ? 'calendar-week-preview'
                : exposeGridKey
                ? 'calendar-month-grid'
                : 'calendar-month-grid-preview',
          ),
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cellCount,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: cellExtent,
          ),
          itemBuilder: (context, index) {
            final date = firstGridDate.add(Duration(days: index));
            return _buildDateCell(
              context,
              date,
              monthOnly: monthOnly,
              compact: compact,
              monthContext: monthContext,
              selectedDateContext: selectedDateContext,
              occurrencesByDateContext: occurrencesByDateContext,
              eventAreaHeight: cellExtent * 0.2,
              tapOpensDay: tapOpensDay,
            );
          },
        );
        if (transparentSurface) {
          return grid;
        }
        return PremiumSurface(
          padding: EdgeInsets.all(surfacePadding),
          radius: AppRadius.section,
          elevation: AppElevation.subtle,
          child: grid,
        );
      },
    );
  }

  int _monthGridCellCount() {
    return 42;
  }

  DateTime _monthGridStartDate(DateTime month) {
    final firstOfMonth = DateTime(month.year, month.month);
    return firstOfMonth.subtract(
      Duration(days: firstOfMonth.weekday % DateTime.daysPerWeek),
    );
  }

  void _showCountdownSheet() {
    _refreshUpcomingOccurrences();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: _buildCountdownSheet(),
      ),
    );
  }

  Widget _buildCountdownSheet() {
    return DraggableScrollableSheet(
      key: const ValueKey('calendar-countdown-sheet'),
      initialChildSize: 0.14,
      minChildSize: 0.1,
      maxChildSize: 0.7,
      snap: true,
      snapSizes: const [0.14, 0.42],
      builder: (context, scrollController) {
        final theme = Theme.of(context);
        final localizations = MaterialLocalizations.of(context);
        return Material(
          color: theme.colorScheme.surfaceContainerLow,
          elevation: 3,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListView(
            key: const ValueKey('calendar-countdown-content'),
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Center(
                child: Semantics(
                  container: true,
                  label: 'Countdown panel drag handle',
                  child: Container(
                    width: 34,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Countdown',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              if (_upcomingOccurrences.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'No upcoming reminders',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final occurrence in _upcomingOccurrences.take(12))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.event_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(
                      occurrence.reminder.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${localizations.formatMediumDate(occurrence.dateTime)} · '
                      '${TimeOfDay.fromDateTime(occurrence.dateTime).format(context)}',
                    ),
                    onTap: () => _openEditReminder(occurrence.reminder),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDateCell(
    BuildContext context,
    DateTime date, {
    required bool monthOnly,
    bool compact = false,
    DateTime? monthContext,
    DateTime? selectedDateContext,
    Map<DateTime, List<CalendarOccurrence>>? occurrencesByDateContext,
    required double eventAreaHeight,
    bool tapOpensDay = false,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final occurrences = _occurrencesFor(date, occurrencesByDateContext);
    final selected = _sameDay(date, selectedDateContext ?? _selectedDate);
    final today = _isToday(date);
    final displayedMonth = monthContext ?? _displayedMonth;
    final inDisplayedMonth =
        date.month == displayedMonth.month && date.year == displayedMonth.year;
    final weekend =
        date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    final markerExtent = compact
        ? 11.0
        : eventAreaHeight <= 12
        ? (eventAreaHeight * 3).clamp(17.0, 30.0).toDouble()
        : 36.0;
    final dateColor = !inDisplayedMonth
        ? colors.onSurfaceVariant.withValues(alpha: 0.45)
        : selected
        ? colors.onPrimary
        : today
        ? colors.onSurface
        : weekend
        ? colors.tertiary
        : colors.onSurface;
    final eventCount = occurrences.length;
    final fullDate = MaterialLocalizations.of(context).formatFullDate(date);

    return Semantics(
      key: ValueKey('calendar-day-${date.year}-${date.month}-${date.day}'),
      button: true,
      selected: selected,
      hint: tapOpensDay
          ? 'Open day schedule'
          : monthOnly
          ? 'Double tap to open this week'
          : null,
      label: [
        fullDate,
        if (today) 'today',
        if (selected) 'selected',
        if (eventCount > 0)
          '$eventCount ${eventCount == 1 ? 'reminder' : 'reminders'}',
      ].join(', '),
      child: AnimatedContainer(
        key: ValueKey(
          'calendar-day-cell-${date.year}-${date.month}-${date.day}',
        ),
        duration: AppMotion.resolve(context, AppMotion.interaction),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected
              ? colors.primary
              : today
              ? colors.primaryContainer.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: today
              ? Border.all(
                  color: selected ? colors.onPrimary : colors.primary,
                  width: 1.5,
                )
              : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            if (tapOpensDay) {
              _openDayDetails(date);
            } else {
              _selectDate(date);
            }
          },
          onDoubleTap: () {
            if (monthOnly && !tapOpensDay) {
              _selectDate(date);
              _selectViewMode(CalendarViewMode.week);
            }
          },
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 1 : 2,
              compact ? 0 : 2,
              compact ? 1 : 2,
              compact ? 0 : 1,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedContainer(
                  key: ValueKey(
                    'calendar-day-marker-${date.year}-${date.month}-${date.day}',
                  ),
                  duration: AppMotion.resolve(context, AppMotion.interaction),
                  curve: Curves.easeOutCubic,
                  width: markerExtent,
                  height: markerExtent,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(shape: BoxShape.circle),
                  child: AnimatedDefaultTextStyle(
                    duration: AppMotion.resolve(context, AppMotion.interaction),
                    curve: Curves.easeOutCubic,
                    style:
                        (compact
                                ? theme.textTheme.labelSmall
                                : theme.textTheme.labelMedium ??
                                      theme.textTheme.bodyMedium ??
                                      const TextStyle())!
                            .copyWith(
                              color: selected ? colors.onPrimary : dateColor,
                              fontWeight: selected || today
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: compact ? 7 : 16,
                              height: compact ? 1 : null,
                            ),
                    child: Text(
                      key: ValueKey(
                        'calendar-day-number-${date.year}-${date.month}-${date.day}',
                      ),
                      MaterialLocalizations.of(context).formatDecimal(date.day),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
                if (monthOnly)
                  SizedBox(
                    key: ValueKey(
                      'calendar-month-event-area-${date.year}-'
                      '${date.month}-${date.day}',
                    ),
                    height: eventAreaHeight,
                    child: _buildMonthCellEvents(
                      context,
                      occurrences,
                      compact: compact,
                      eventAreaHeight: eventAreaHeight,
                      selected: selected,
                    ),
                  )
                else if (compact)
                  SizedBox(
                    height: 1,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final occurrence in occurrences.take(3))
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: Container(
                              width: 2,
                              height: 2,
                              decoration: BoxDecoration(
                                color:
                                    CalendarColors.forReminder(
                                      occurrence.reminder.id,
                                    ).foreground(
                                      theme.brightness == Brightness.dark,
                                    ),
                                shape: BoxShape.circle,
                                border: selected
                                    ? Border.all(color: colors.onPrimary)
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                else ...[
                  const SizedBox(height: 2),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 3,
                    runSpacing: 2,
                    children: [
                      for (final occurrence in occurrences.take(4))
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: CalendarColors.forReminder(
                              occurrence.reminder.id,
                            ).foreground(theme.brightness == Brightness.dark),
                            shape: BoxShape.circle,
                            border: selected
                                ? Border.all(color: colors.onPrimary)
                                : null,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthCellEvents(
    BuildContext context,
    List<CalendarOccurrence> occurrences, {
    required bool compact,
    required double eventAreaHeight,
    required bool selected,
  }) {
    final theme = Theme.of(context);
    if (occurrences.isEmpty) {
      return const SizedBox.expand();
    }
    final count = occurrences.length;
    if (count <= 3) {
      return Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final occurrence in occurrences.take(3))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Container(
                  width: compact ? 2 : 3,
                  height: compact ? 2 : 3,
                  decoration: BoxDecoration(
                    color: CalendarColors.forReminder(occurrence.reminder.id)
                        .foreground(theme.brightness == Brightness.dark),
                    shape: BoxShape.circle,
                    border: selected
                        ? Border.all(color: theme.colorScheme.onPrimary)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Center(
      child: Text(
        '$count',
        key: ValueKey('calendar-month-event-count-$count'),
        maxLines: 1,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: compact || eventAreaHeight < 10 ? 7 : 9,
          height: 1,
          color: selected
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _openDayDetails(DateTime date) {
    _selectDate(date);
    _selectViewMode(CalendarViewMode.day);
  }

  DateTime _weekStart(DateTime date) =>
      _dateOnly(date).subtract(Duration(days: date.weekday - DateTime.monday));

  Widget _buildEventRow(
    BuildContext context,
    CalendarOccurrence occurrence, {
    bool dense = false,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final eventColor = CalendarColors.forReminder(occurrence.reminder.id);
    final recurrence = occurrence.reminder.recurrenceRule.type;
    final description = occurrence.reminder.description;
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 2 : 5),
      child: Material(
        key: ValueKey(
          'calendar-reminder-${occurrence.reminder.id}-${occurrence.dateTime.day}',
        ),
        color: eventColor.surface(dark),
        borderRadius: BorderRadius.circular(dense ? 4 : 7),
        child: InkWell(
          borderRadius: BorderRadius.circular(dense ? 4 : 7),
          onTap: () => _openEditReminder(occurrence.reminder),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              dense ? 4 : 7,
              dense ? 2 : 6,
              2,
              dense ? 2 : 6,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: dense ? 39 : 63,
                  child: Text(
                    dense
                        ? MaterialLocalizations.of(context).formatTimeOfDay(
                            TimeOfDay.fromDateTime(occurrence.dateTime),
                            alwaysUse24HourFormat: true,
                          )
                        : TimeOfDay.fromDateTime(occurrence.dateTime)
                              .format(context),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style:
                        (dense
                                ? theme.textTheme.labelSmall
                                : theme.textTheme.labelSmall)
                            ?.copyWith(
                              color: eventColor.foreground(dark),
                              fontSize: dense ? 9 : null,
                              fontWeight: FontWeight.w800,
                            ),
                  ),
                ),
                if (!dense)
                  Container(
                    width: 3,
                    height: 31,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: eventColor.foreground(dark),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        occurrence.reminder.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            (dense
                                    ? theme.textTheme.labelSmall
                                    : theme.textTheme.bodyMedium)
                                ?.copyWith(
                                  fontSize: dense ? 10 : null,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      if (!dense &&
                          description != null &&
                          description.trim().isNotEmpty)
                        Text(
                          description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (recurrence != RecurrenceType.none)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: dense ? 1 : 3),
                    child: Icon(
                      Icons.repeat,
                      size: dense ? 10 : 15,
                      color: eventColor.foreground(dark),
                    ),
                  ),
                if (occurrence.reminder.notificationMode ==
                    ReminderNotificationMode.alarmAndNotification)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: dense ? 1 : 3),
                    child: Icon(
                      Icons.alarm,
                      size: dense ? 10 : 15,
                      color: eventColor.foreground(dark),
                    ),
                  ),
                if (!dense)
                  PopupMenuButton<String>(
                    tooltip: 'More actions for ${occurrence.reminder.title}',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    iconSize: 17,
                    onSelected: (action) {
                      if (action == 'edit') {
                        _openEditReminder(occurrence.reminder);
                      } else if (action == 'delete') {
                        _deleteReminder(occurrence.reminder);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Delete'),
                          contentPadding: EdgeInsets.zero,
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

class _YearPickerDialog extends StatefulWidget {
  const _YearPickerDialog({
    required this.selectedYear,
    required this.currentYear,
  });

  final int selectedYear;
  final int currentYear;

  static const firstYear = 1900;
  static const lastYear = 2100;

  @override
  State<_YearPickerDialog> createState() => _YearPickerDialogState();
}

class _YearPickerDialogState extends State<_YearPickerDialog> {
  static const _columnCount = 4;
  static const _rowExtent = 48.0;
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    final selectedIndex = widget.selectedYear - _YearPickerDialog.firstYear;
    _controller = ScrollController(
      initialScrollOffset: (selectedIndex ~/ _columnCount) * (_rowExtent + 4),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Dialog(
      child: SizedBox(
        width: 340,
        height: 360,
        child: GridView.builder(
          key: const ValueKey('calendar-year-picker'),
          controller: _controller,
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _columnCount,
            mainAxisExtent: _rowExtent,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount:
              _YearPickerDialog.lastYear - _YearPickerDialog.firstYear + 1,
          itemBuilder: (context, index) {
            final year = _YearPickerDialog.firstYear + index;
            final selected = year == widget.selectedYear;
            final isCurrent = year == widget.currentYear;
            return Semantics(
              key: ValueKey('calendar-year-option-$year'),
              button: true,
              selected: selected,
              label: '$year',
              child: Material(
                color: selected ? scheme.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).pop(year),
                  child: Center(
                    child: Text(
                      '$year',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: selected
                            ? scheme.onPrimaryContainer
                            : isCurrent
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        fontWeight: selected || isCurrent
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
