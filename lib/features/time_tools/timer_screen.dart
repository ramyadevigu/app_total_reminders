import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/app_navigation_drawer.dart';
import '../../theme/app_design_tokens.dart';
import '../../theme/premium_surface.dart';

class TimerScreen extends StatefulWidget {
  const TimerScreen({
    super.key,
    required this.appMenu,
    this.navigationDrawer,
    this.useInternalNavigationDrawer = true,
  });

  final Widget appMenu;
  final Widget? navigationDrawer;
  final bool useInternalNavigationDrawer;

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  static const _savedTimersKey = 'savedTimers';

  final List<_SavedTimer> _savedTimers = [];
  Timer? _ticker;
  bool _isLoading = true;
  bool _tickerModeEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSavedTimers();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final timer in _savedTimers) {
      timer.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerModeEnabled = TickerMode.valuesOf(context).enabled;
    if (_tickerModeEnabled == tickerModeEnabled) {
      return;
    }
    _tickerModeEnabled = tickerModeEnabled;
    if (_tickerModeEnabled) {
      _updateRunningTimers();
    } else {
      _syncTicker();
    }
  }

  Future<void> _loadSavedTimers() async {
    final loadedTimers = <_SavedTimer>[];
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(_savedTimersKey);
      if (encoded != null) {
        final decoded = jsonDecode(encoded);
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is! Map<String, dynamic>) {
              continue;
            }
            final id = entry['id'];
            final seconds = entry['seconds'];
            if (id is String && seconds is int && seconds > 0) {
              loadedTimers.add(
                _SavedTimer(
                  id: id,
                  duration: Duration(seconds: seconds),
                ),
              );
            }
          }
        }
      }
    } on Exception {
      // Keep the timer list usable if saved data cannot be decoded.
    }
    if (mounted) {
      setState(() {
        _savedTimers.addAll(loadedTimers);
        _isLoading = false;
      });
    } else {
      for (final timer in loadedTimers) {
        timer.dispose();
      }
    }
  }

  Future<void> _persistSavedTimers() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _savedTimers
          .map((timer) => {'id': timer.id, 'seconds': timer.duration.inSeconds})
          .toList(),
    );
    await preferences.setString(_savedTimersKey, encoded);
  }

  void _addTimer(Duration duration) {
    final timer = _SavedTimer(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      duration: duration,
    );
    setState(() => _savedTimers.insert(0, timer));
    unawaited(_persistSavedTimers());
  }

  void _deleteTimer(_SavedTimer timer) {
    setState(() => _savedTimers.remove(timer));
    _syncTicker();
    WidgetsBinding.instance.addPostFrameCallback((_) => timer.dispose());
    unawaited(_persistSavedTimers());
  }

  void _toggleTimer(_SavedTimer timer) {
    if (timer.isRunning) {
      final remaining = timer.deadline!.difference(DateTime.now());
      timer.update(
        remaining: remaining > Duration.zero ? remaining : Duration.zero,
        isRunning: false,
        isFinished: remaining <= Duration.zero,
      );
      timer.deadline = null;
    } else {
      final remaining = timer.remaining <= Duration.zero
          ? timer.duration
          : timer.remaining;
      timer.update(remaining: remaining, isRunning: true, isFinished: false);
      timer.deadline = DateTime.now().add(remaining);
    }
    _syncTicker();
  }

  void _updateRunningTimers() {
    if (!_tickerModeEnabled) {
      _syncTicker();
      return;
    }
    final now = DateTime.now();
    for (final timer in _savedTimers.where((timer) => timer.isRunning)) {
      final remaining = timer.deadline!.difference(now);
      if (remaining <= Duration.zero) {
        timer.update(
          remaining: Duration.zero,
          isRunning: false,
          isFinished: true,
        );
        timer.deadline = null;
      } else {
        timer.update(remaining: remaining);
      }
    }
    _syncTicker();
  }

  void _syncTicker() {
    if (_tickerModeEnabled &&
        _savedTimers.any((savedTimer) => savedTimer.isRunning)) {
      _ticker ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
        _updateRunningTimers();
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _showAddTimerSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => _TimerSetupSheet(onSave: _addTimer),
    );
  }

  String _timerLabel(Duration duration) {
    if (duration.inHours > 0) {
      final minutes = duration.inMinutes % 60;
      return minutes == 0
          ? '${duration.inHours}h timer'
          : '${duration.inHours}h ${minutes}m timer';
    }
    if (duration.inMinutes > 0) {
      final seconds = duration.inSeconds % 60;
      return seconds == 0
          ? '${duration.inMinutes}m timer'
          : '${duration.inMinutes}m ${seconds}s timer';
    }
    return '${duration.inSeconds}s timer';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: widget.useInternalNavigationDrawer
          ? widget.navigationDrawer
          : null,
      appBar: AppBar(
        title: const Text('Timers'),
        leading: Builder(
          builder: (context) => IconButton(
            key: const ValueKey('global-navigation-button'),
            tooltip: 'Open navigation menu',
            onPressed: () => AppNavigationDrawerHost.openDrawer(context),
            icon: const Icon(Icons.menu_rounded),
          ),
        ),
        actions: [widget.appMenu],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _savedTimers.isEmpty
            ? const _EmptyTimersState()
            : LayoutBuilder(
                builder: (context, constraints) {
                  return ListView.separated(
                    key: const ValueKey('saved-timer-grid'),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: _savedTimers.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, indent: 4, endIndent: 4),
                    itemBuilder: (context, index) {
                      final timer = _savedTimers[index];
                      return _SavedTimerCard(
                        key: ValueKey('timer-card-${timer.id}'),
                        timer: timer,
                        title: _timerLabel(timer.duration),
                        onToggle: () => _toggleTimer(timer),
                        onDelete: () => _deleteTimer(timer),
                      );
                    },
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('timer-add'),
        tooltip: 'Add timer',
        onPressed: _showAddTimerSheet,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _SavedTimer {
  _SavedTimer({required this.id, required this.duration})
    : state = ValueNotifier(_SavedTimerState(remaining: duration));

  final String id;
  final Duration duration;
  final ValueNotifier<_SavedTimerState> state;
  DateTime? deadline;

  Duration get remaining => state.value.remaining;
  bool get isRunning => state.value.isRunning;
  bool get isFinished => state.value.isFinished;

  void update({Duration? remaining, bool? isRunning, bool? isFinished}) {
    final current = state.value;
    state.value = _SavedTimerState(
      remaining: remaining ?? current.remaining,
      isRunning: isRunning ?? current.isRunning,
      isFinished: isFinished ?? current.isFinished,
    );
  }

  void dispose() => state.dispose();
}

class _SavedTimerState {
  const _SavedTimerState({
    required this.remaining,
    this.isRunning = false,
    this.isFinished = false,
  });

  final Duration remaining;
  final bool isRunning;
  final bool isFinished;
}

class _SavedTimerCard extends StatelessWidget {
  const _SavedTimerCard({
    super.key,
    required this.timer,
    required this.title,
    required this.onToggle,
    required this.onDelete,
  });

  final _SavedTimer timer;
  final String title;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_SavedTimerState>(
      valueListenable: timer.state,
      builder: (context, state, _) {
        final colorScheme = Theme.of(context).colorScheme;
        final progress = timer.duration.inMilliseconds == 0
            ? 0.0
            : (state.remaining.inMilliseconds / timer.duration.inMilliseconds)
                  .clamp(0.0, 1.0);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTimerDuration(state.remaining),
                      key: ValueKey('timer-card-time-${timer.id}'),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontWeight: FontWeight.w300,
                        color: state.isFinished
                            ? colorScheme.error
                            : colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox.square(
                dimension: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.square(
                      dimension: 64,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 3,
                        color: state.isFinished
                            ? colorScheme.error
                            : colorScheme.primary,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    IconButton(
                      key: ValueKey('timer-card-action-${timer.id}'),
                      tooltip: state.isRunning
                          ? 'Pause $title'
                          : state.isFinished
                          ? 'Restart $title'
                          : 'Start $title',
                      onPressed: onToggle,
                      icon: Icon(
                        state.isRunning
                            ? Icons.pause
                            : state.isFinished
                            ? Icons.replay
                            : Icons.play_arrow,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('timer-card-delete-${timer.id}'),
                tooltip: 'Delete $title',
                onPressed: onDelete,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _formatTimerDuration(Duration duration) {
  final totalSeconds = (duration.inMilliseconds / 1000).ceil();
  final hours = totalSeconds ~/ 3600;
  final minutes = totalSeconds % 3600 ~/ 60;
  final seconds = totalSeconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  if (hours == 0) {
    return '$mm:$ss';
  }
  return '${hours.toString().padLeft(2, '0')}:$mm:$ss';
}

class _EmptyTimersState extends StatelessWidget {
  const _EmptyTimersState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: PremiumSurface(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
            radius: AppRadius.section,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.hourglass_empty,
                    size: 32,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'No saved timers',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Add a timer to keep it here for later.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimerSetupSheet extends StatefulWidget {
  const _TimerSetupSheet({required this.onSave});

  final ValueChanged<Duration> onSave;

  @override
  State<_TimerSetupSheet> createState() => _TimerSetupSheetState();
}

class _TimerSetupSheetState extends State<_TimerSetupSheet> {
  static const _quickPresets = <Duration>[
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 30),
  ];
  static const _keypadValues = <String>[
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '00',
    '0',
    'backspace',
  ];

  String _digits = '';

  Duration get _selectedDuration {
    final time = _digits.padLeft(6, '0');
    return Duration(
      hours: int.parse(time.substring(0, 2)),
      minutes: int.parse(time.substring(2, 4)),
      seconds: int.parse(time.substring(4, 6)),
    );
  }

  String get _timeDigits => _digits.padLeft(6, '0');

  void _append(String value) {
    if (_digits.length >= 6) {
      return;
    }
    setState(() {
      _digits = (_digits + value).substring(
        0,
        (_digits.length + value.length).clamp(0, 6),
      );
    });
  }

  void _backspace() {
    if (_digits.isEmpty) {
      return;
    }
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  void _selectPreset(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    setState(() {
      _digits = '$hours$minutes$seconds'.replaceFirst(RegExp(r'^0+'), '');
    });
  }

  String _presetLabel(Duration duration) {
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds} sec';
    }
    return '${duration.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _selectedDuration > Duration.zero;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.92),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                _TimeDigit(value: _timeDigits.substring(0, 2), label: 'Hours'),
                _TimeDigit(
                  value: _timeDigits.substring(2, 4),
                  label: 'Minutes',
                ),
                _TimeDigit(
                  value: _timeDigits.substring(4, 6),
                  label: 'Seconds',
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in _quickPresets)
                  ChoiceChip(
                    key: ValueKey('timer-preset-${preset.inSeconds}'),
                    label: Text(_presetLabel(preset)),
                    selected: _selectedDuration == preset,
                    onSelected: (_) => _selectPreset(preset),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 8,
                children: [
                  for (final value in _keypadValues)
                    TextButton(
                      key: ValueKey('timer-key-$value'),
                      onPressed: value == 'backspace'
                          ? _backspace
                          : () => _append(value),
                      child: value == 'backspace'
                          ? const Icon(Icons.backspace_outlined)
                          : Text(value, style: theme.textTheme.titleLarge),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                key: const ValueKey('timer-save'),
                onPressed: canSave
                    ? () {
                        widget.onSave(_selectedDuration);
                        Navigator.of(context).pop();
                      }
                    : null,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save timer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeDigit extends StatelessWidget {
  const _TimeDigit({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: theme.textTheme.displayMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
          Text(label, style: theme.textTheme.labelLarge),
        ],
      ),
    );
  }
}
