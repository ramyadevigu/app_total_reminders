import 'dart:async';

import 'package:flutter/material.dart';

import '../features/auth/widgets/authentication_gate.dart';
import '../features/calender/models/calendar_view_mode.dart';
import '../features/calender/calender_screen.dart';
import '../features/notes/notes_screen.dart';
import '../features/my_day/my_day_screen.dart';
import '../features/notes/models/note_workspace_models.dart';
import '../features/auth/services/google_auth_service.dart';
import '../features/auth/screens/profile_screen.dart';
import '../features/notes/services/note_workspace_storage.dart';
import '../features/reminders/screens/add_reminder_screen.dart';
import '../features/reminders/screens/alarm_ringing_screen.dart';
import '../features/reminders/models/reminder.dart';
import '../features/reminders/services/reminder_storage.dart';
import '../features/reminders/reminders_screen.dart';
import '../features/settings/services/reminder_preferences_store.dart';
import '../features/settings/settings_screen.dart';
import '../features/time_tools/stopwatch_screen.dart';
import '../features/time_tools/timer_screen.dart';
import '../services/notification_service.dart';
import '../theme/app_backdrop.dart';
import '../theme/app_design_tokens.dart';
import '../theme/app_theme.dart';
import '../theme/theme_preference_store.dart';
import '../widgets/app_navigation_drawer.dart';

enum _AppMenuAction { settings, help, feedback }

class AppSmarana extends StatefulWidget {
  const AppSmarana({
    super.key,
    this.initialThemeMode = ThemeMode.system,
    this.initialAccentColor = defaultAccentColor,
    this.themePreferenceStore = const ThemePreferenceStore(),
    this.initializeServicesAfterFirstFrame,
    this.ringingAlarmIds,
    this.stoppedAlarmIds,
    this.readActiveAlarmReminderId,
    this.loadAlarmReminders,
  });

  final ThemeMode initialThemeMode;
  final Color initialAccentColor;
  final ThemePreferenceStore themePreferenceStore;
  final Future<void> Function()? initializeServicesAfterFirstFrame;
  final Stream<String>? ringingAlarmIds;
  final Stream<String>? stoppedAlarmIds;
  final Future<String?> Function()? readActiveAlarmReminderId;
  final Future<List<Reminder>> Function()? loadAlarmReminders;

  @override
  State<AppSmarana> createState() => _AppSmaranaState();
}

class _AppSmaranaState extends State<AppSmarana> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late ThemeMode _themeMode;
  late Color _accentColor;
  StreamSubscription<String>? _notificationSubscription;
  StreamSubscription<String>? _alarmSubscription;
  StreamSubscription<String>? _alarmStoppedSubscription;
  bool _openingNotificationReminder = false;
  bool _openingRingingAlarm = false;
  String? _ringingAlarmId;
  String? _pendingRingingAlarmId;
  Route<void>? _ringingAlarmRoute;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
    _accentColor = widget.initialAccentColor;
    final notifications = NotificationService.instance;
    _notificationSubscription = notifications.openedReminderIds.listen(
      _openReminderFromNotification,
    );
    _alarmSubscription =
        (widget.ringingAlarmIds ?? notifications.ringingReminderIds).listen(
          _openRingingAlarm,
        );
    _alarmStoppedSubscription =
        (widget.stoppedAlarmIds ?? notifications.stoppedReminderIds).listen(
          _closeRingingAlarm,
        );
    final initializeServicesAfterFirstFrame =
        widget.initializeServicesAfterFirstFrame;
    if (initializeServicesAfterFirstFrame != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          _initializeAfterFirstFrame(initializeServicesAfterFirstFrame),
        );
      });
    }
  }

  @override
  void dispose() {
    final subscription = _notificationSubscription;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    final alarmSubscription = _alarmSubscription;
    if (alarmSubscription != null) {
      unawaited(alarmSubscription.cancel());
    }
    final alarmStoppedSubscription = _alarmStoppedSubscription;
    if (alarmStoppedSubscription != null) {
      unawaited(alarmStoppedSubscription.cancel());
    }
    super.dispose();
  }

  Future<void> _initializeAfterFirstFrame(
    Future<void> Function() initializeServices,
  ) async {
    try {
      await initializeServices();
    } on Object catch (error, stackTrace) {
      _reportStartupError(error, stackTrace);
      return;
    }

    final launchReminderId = NotificationService.instance
        .takeInitialReminderId();
    try {
      await ReminderStorage().rescheduleAllReminders();
    } on Object catch (error, stackTrace) {
      _reportStartupError(error, stackTrace);
    }

    if (!mounted) {
      return;
    }

    unawaited(_restoreRingingAlarmWithErrorReporting());
    if (launchReminderId != null) {
      unawaited(_openReminderFromNotification(launchReminderId));
    }
  }

  Future<void> _restoreRingingAlarmWithErrorReporting() async {
    try {
      await _restoreRingingAlarm();
    } on Object catch (error, stackTrace) {
      _reportStartupError(error, stackTrace);
    }
  }

  void _reportStartupError(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'app startup',
      ),
    );
    if (!mounted) {
      return;
    }
    final context = _navigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: const Text(
            'Some reminders could not be restored or scheduled.',
          ),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: _retryAfterStartupError,
          ),
        ),
      );
    }
  }

  void _retryAfterStartupError() {
    final initializeServices = widget.initializeServicesAfterFirstFrame;
    if (initializeServices != null) {
      unawaited(_initializeAfterFirstFrame(initializeServices));
    }
  }

  Future<void> _restoreRingingAlarm() async {
    final reminderId = await _readActiveAlarmReminderId();
    if (reminderId != null) {
      await _openRingingAlarm(reminderId);
    }
  }

  Future<String?> _readActiveAlarmReminderId() {
    final read = widget.readActiveAlarmReminderId;
    return read == null
        ? NotificationService.instance.activeAlarmReminderId()
        : read();
  }

  Future<List<Reminder>> _loadAlarmReminders() {
    final load = widget.loadAlarmReminders;
    return load == null ? ReminderStorage().getReminders() : load();
  }

  Future<void> _openRingingAlarm(String reminderId) async {
    if (!mounted) {
      return;
    }
    if (_openingRingingAlarm) {
      if (_ringingAlarmId != reminderId) {
        _pendingRingingAlarmId = reminderId;
        _dismissRingingAlarmRoute();
      }
      return;
    }

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openRingingAlarm(reminderId);
      });
      return;
    }

    _openingRingingAlarm = true;
    Route<void>? ringingRoute;
    try {
      final activeReminderId = await _readActiveAlarmReminderId();
      if (activeReminderId != reminderId || !mounted) {
        return;
      }
      final reminders = await _loadAlarmReminders();
      Reminder? ringingReminder;
      for (final reminder in reminders) {
        if (reminder.id == reminderId) {
          ringingReminder = reminder;
          break;
        }
      }
      if (ringingReminder != null && mounted) {
        _ringingAlarmId = reminderId;
        ringingRoute = MaterialPageRoute<void>(
          builder: (_) => AlarmRingingScreen(reminder: ringingReminder!),
          fullscreenDialog: true,
        );
        _ringingAlarmRoute = ringingRoute;
        await navigator.push<void>(ringingRoute);
      }
    } on Exception catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'alarm ringing screen',
        ),
      );
    } finally {
      _ringingAlarmId = null;
      if (identical(_ringingAlarmRoute, ringingRoute)) {
        _ringingAlarmRoute = null;
      }
      _openingRingingAlarm = false;
      final pendingReminderId = _pendingRingingAlarmId;
      _pendingRingingAlarmId = null;
      if (pendingReminderId != null && mounted) {
        unawaited(_openRingingAlarm(pendingReminderId));
      }
    }
  }

  void _closeRingingAlarm(String reminderId) {
    if (!mounted || _ringingAlarmId != reminderId) {
      return;
    }

    _dismissRingingAlarmRoute();
  }

  void _dismissRingingAlarmRoute() {
    final navigator = _navigatorKey.currentState;
    final route = _ringingAlarmRoute;
    if (navigator != null && route != null && route.isActive) {
      _ringingAlarmRoute = null;
      navigator.removeRoute(route);
    }
  }

  Future<void> _openReminderFromNotification(String reminderId) async {
    if (_openingNotificationReminder || !mounted) {
      return;
    }

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openReminderFromNotification(reminderId);
      });
      return;
    }

    _openingNotificationReminder = true;
    try {
      final reminders = await ReminderStorage().getReminders();
      for (final reminder in reminders) {
        if (reminder.id == reminderId && mounted) {
          await navigator.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => AddReminderScreen(reminder: reminder),
            ),
          );
          return;
        }
      }
    } on Exception catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stackTrace),
      );
    } finally {
      _openingNotificationReminder = false;
    }
  }

  Future<void> _changeThemeMode(ThemeMode themeMode) async {
    if (_themeMode == themeMode) {
      return;
    }

    setState(() {
      _themeMode = themeMode;
    });
    await widget.themePreferenceStore.saveThemeMode(themeMode);
  }

  Future<void> _changeAccentColor(Color accentColor) async {
    if (_accentColor == accentColor) {
      return;
    }

    setState(() => _accentColor = accentColor);
    await widget.themePreferenceStore.saveAccentColor(accentColor);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Total Reminders',
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          AppBackdrop(child: child ?? const SizedBox.shrink()),
      theme: buildLightTheme(_accentColor),
      darkTheme: buildDarkTheme(_accentColor),
      themeMode: _themeMode,
      themeAnimationDuration: AppMotion.theme,
      themeAnimationCurve: AppMotion.standard,
      home: AuthenticationGate(
        authenticatedChild: HomeScreen(
          selectedThemeMode: _themeMode,
          onThemeModeChanged: _changeThemeMode,
          selectedAccentColor: _accentColor,
          onAccentColorChanged: _changeAccentColor,
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.selectedThemeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.selectedAccentColor = defaultAccentColor,
    this.onAccentColorChanged,
  });

  final ThemeMode selectedThemeMode;
  final Future<void> Function(ThemeMode)? onThemeModeChanged;
  final Color selectedAccentColor;
  final Future<void> Function(Color)? onAccentColorChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _showingMyDay = false;
  final ValueNotifier<int> _noteWorkspaceRevision = ValueNotifier(0);
  final Set<int> _visitedTabs = {0};
  final GlobalKey<ScaffoldState> _homeScaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<NotesScreenState> _notesScreenKey =
      GlobalKey<NotesScreenState>();
  final NoteWorkspaceStorage _noteWorkspaceStorage = NoteWorkspaceStorage();
  final ReminderPreferencesStore _preferencesStore =
      const ReminderPreferencesStore();
  CalendarViewMode _calendarViewMode = CalendarViewMode.month;

  @override
  void dispose() {
    _noteWorkspaceRevision.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadCalendarViewMode();
  }

  Future<void> _loadCalendarViewMode() async {
    try {
      final defaults = await _preferencesStore.loadDefaults();
      if (!mounted) {
        return;
      }
      setState(() {
        _calendarViewMode = defaults.calendarViewMode;
      });
    } on Exception {
      // Keep default view mode if preferences cannot be read.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedDestination = _showingMyDay
        ? AppNavigationDestination.myDay
        : switch (_currentIndex) {
            0 => AppNavigationDestination.calendar,
            1 => AppNavigationDestination.notes,
            2 => AppNavigationDestination.reminders,
            3 => AppNavigationDestination.stopwatch,
            _ => AppNavigationDestination.timer,
          };
    return AppNavigationDrawerHost(
      onOpenDrawer: () => _homeScaffoldKey.currentState?.openDrawer(),
      child: Scaffold(
        key: _homeScaffoldKey,
        drawer: _buildNavigationDrawer(selectedDestination),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: IndexedStack(
              index: _showingMyDay ? 5 : _currentIndex,
              children: List<Widget>.generate(6, _buildTab),
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          indicatorColor: colorScheme.primary.withValues(
            alpha: Theme.of(context).brightness == Brightness.light
                ? 0.12
                : 0.2,
          ),
          onDestinationSelected: (index) {
            setState(() {
              _visitedTabs.add(index);
              _currentIndex = index;
              _showingMyDay = false;
            });
          },
          destinations: [
            NavigationDestination(
              key: ValueKey('nav-calendar'),
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(
                Icons.calendar_month,
                color: colorScheme.primary,
              ),
              label: 'Calendar',
            ),
            NavigationDestination(
              key: ValueKey('nav-notes'),
              icon: Icon(Icons.sticky_note_2_outlined),
              selectedIcon: Icon(
                Icons.sticky_note_2,
                color: colorScheme.primary,
              ),
              label: 'Notes',
            ),
            NavigationDestination(
              key: ValueKey('nav-alarms'),
              icon: Icon(Icons.notifications_none),
              selectedIcon: Icon(
                Icons.notifications_active,
                color: colorScheme.primary,
              ),
              label: 'Alarms',
            ),
            NavigationDestination(
              key: ValueKey('nav-stopwatch'),
              icon: Icon(Icons.av_timer_outlined),
              selectedIcon: Icon(Icons.av_timer, color: colorScheme.primary),
              label: 'Stopwatch',
            ),
            NavigationDestination(
              key: ValueKey('nav-timer'),
              icon: Icon(Icons.hourglass_bottom_outlined),
              selectedIcon: Icon(
                Icons.hourglass_bottom,
                color: colorScheme.primary,
              ),
              label: 'Timer',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(int index) {
    if (!_visitedTabs.contains(index)) {
      return const SizedBox.shrink();
    }

    final tab = switch (index) {
      0 => CalendarScreen(
        viewMode: _calendarViewMode,
        onViewModeChanged: _changeCalendarViewMode,
        appMenu: _buildAppMenu(),
        navigationDrawer: _buildNavigationDrawer(
          AppNavigationDestination.calendar,
        ),
        useInternalNavigationDrawer: false,
      ),
      1 => NotesScreen(
        key: _notesScreenKey,
        appMenu: _buildAppMenu(),
        navigationDrawer: _buildNavigationDrawer(
          AppNavigationDestination.notes,
        ),
        useInternalNavigationDrawer: false,
        onBackToSmarana: _returnToCalendar,
        onWorkspaceChanged: _refreshNoteWorkspace,
        onOpenSettings: () => _handleAppMenuAction(_AppMenuAction.settings),
        onOpenHelp: () => _handleAppMenuAction(_AppMenuAction.help),
        onOpenFeedback: () => _handleAppMenuAction(_AppMenuAction.feedback),
      ),
      2 => RemindersScreen(
        title: 'Alarms',
        appMenu: _buildAppMenu(),
        navigationDrawer: _buildNavigationDrawer(
          AppNavigationDestination.reminders,
        ),
        useInternalNavigationDrawer: false,
      ),
      3 => StopwatchScreen(
        appMenu: _buildAppMenu(),
        navigationDrawer: _buildNavigationDrawer(
          AppNavigationDestination.stopwatch,
        ),
        useInternalNavigationDrawer: false,
      ),
      4 => TimerScreen(
        appMenu: _buildAppMenu(),
        navigationDrawer: _buildNavigationDrawer(
          AppNavigationDestination.timer,
        ),
        useInternalNavigationDrawer: false,
      ),
      5 => MyDayScreen(
        appMenu: _buildAppMenu(),
        navigationDrawer: _buildNavigationDrawer(
          AppNavigationDestination.myDay,
        ),
        onNoteSelected: _openNoteFromDrawer,
      ),
      _ => const SizedBox.shrink(),
    };
    return TickerMode(
      enabled: index == (_showingMyDay ? 5 : _currentIndex),
      child: tab,
    );
  }

  Widget _buildNavigationDrawer(AppNavigationDestination selected) {
    return AppNavigationDrawer(
      selectedDestination: selected,
      workspaceStorage: _noteWorkspaceStorage,
      workspaceChanges: _noteWorkspaceRevision,
      onDestinationSelected: _selectNavigationDestination,
      onNotebookSelected: _openNotebookFromDrawer,
      onNoteSelected: _openNoteFromDrawer,
    );
  }

  void _selectNavigationDestination(AppNavigationDestination destination) {
    switch (destination) {
      case AppNavigationDestination.profile:
        final user = GoogleAuthService.instance.currentUser;
        if (user != null) {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => ProfileScreen(
                user: user,
                navigationDrawer: _buildNavigationDrawer(
                  AppNavigationDestination.profile,
                ),
              ),
            ),
          );
        }
        return;
      case AppNavigationDestination.search:
        _showSearch();
        return;
      case AppNavigationDestination.settings:
        _handleAppMenuAction(_AppMenuAction.settings);
        return;
      case AppNavigationDestination.calendar:
        _navigateToTab(0);
        return;
      case AppNavigationDestination.myDay:
        _navigateToMyDay();
        return;
      case AppNavigationDestination.notes:
        _navigateToTab(1);
        return;
      case AppNavigationDestination.reminders:
        _navigateToTab(2);
        return;
      case AppNavigationDestination.stopwatch:
        _navigateToTab(3);
        return;
      case AppNavigationDestination.timer:
        _navigateToTab(4);
        return;
    }
  }

  void _openNotebookFromDrawer(String notebookId) {
    _navigateToTab(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notesScreenKey.currentState?.openNotebookById(notebookId);
    });
  }

  void _openNoteFromDrawer(String notebookId, NoteEntry note) {
    _navigateToTab(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notesScreenKey.currentState?.openNoteById(notebookId, note.id);
    });
  }

  void _refreshNoteWorkspace() {
    _noteWorkspaceRevision.value++;
  }

  Future<void> _showSearch() async {
    final controller = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search notes'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search titles and note content',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Search'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (query == null || query.trim().isEmpty) return;
    _navigateToTab(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notesScreenKey.currentState?.searchFor(query.trim());
    });
  }

  Widget _buildAppMenu() {
    return PopupMenuButton<_AppMenuAction>(
      key: const ValueKey('app-overflow-menu'),
      tooltip: 'More options',
      icon: const Icon(Icons.more_vert),
      onSelected: _handleAppMenuAction,
      itemBuilder: (context) => const [
        PopupMenuItem<_AppMenuAction>(
          value: _AppMenuAction.settings,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.settings_outlined),
            title: Text('Settings'),
          ),
        ),
        PopupMenuItem<_AppMenuAction>(
          value: _AppMenuAction.help,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.help_outline),
            title: Text('Help'),
          ),
        ),
        PopupMenuItem<_AppMenuAction>(
          value: _AppMenuAction.feedback,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.feedback_outlined),
            title: Text('Send Feedback'),
          ),
        ),
      ],
    );
  }

  Future<void> _handleAppMenuAction(_AppMenuAction action) async {
    switch (action) {
      case _AppMenuAction.settings:
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => SettingsScreen(
              navigationDrawer: _buildNavigationDrawer(
                AppNavigationDestination.settings,
              ),
              selectedThemeMode: widget.selectedThemeMode,
              selectedAccentColor: widget.selectedAccentColor,
              selectedCalendarViewMode: _calendarViewMode,
              onCalendarViewModeChanged: _changeCalendarViewMode,
              onThemeModeChanged: _changeThemeMode,
              onAccentColorChanged: widget.onAccentColorChanged,
            ),
          ),
        );
      case _AppMenuAction.help:
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.help_outline),
            title: const Text('Help'),
            content: const Text(
              'Use Calendar to view reminders, Notes to save ideas, and '
              'Alarms to manage your reminders.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      case _AppMenuAction.feedback:
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.feedback_outlined),
            title: const Text('Send Feedback'),
            content: const Text('Feedback delivery is not configured yet.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
    }
  }

  Future<void> _changeThemeMode(ThemeMode themeMode) async {
    await widget.onThemeModeChanged?.call(themeMode);
  }

  Future<void> _changeCalendarViewMode(CalendarViewMode viewMode) async {
    if (_calendarViewMode == viewMode) {
      return;
    }
    setState(() {
      _calendarViewMode = viewMode;
    });
    final defaults = await _preferencesStore.loadDefaults();
    await _preferencesStore.saveDefaults(
      defaults.copyWith(calendarViewMode: viewMode),
    );
  }

  void _returnToCalendar() {
    if (_currentIndex == 0 && !_showingMyDay) {
      return;
    }
    setState(() {
      _currentIndex = 0;
      _showingMyDay = false;
    });
  }

  void _navigateToTab(int index) {
    if (index < 0 || index >= 5) {
      return;
    }
    _popToHome();
    setState(() {
      _visitedTabs.add(index);
      _currentIndex = index;
      _showingMyDay = false;
    });
  }

  void _navigateToMyDay() {
    _popToHome();
    setState(() {
      _visitedTabs.add(5);
      _showingMyDay = true;
    });
  }

  void _popToHome() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
  }
}
