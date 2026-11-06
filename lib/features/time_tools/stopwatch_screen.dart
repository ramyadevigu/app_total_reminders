import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/app_navigation_drawer.dart';

class _StopwatchLap {
  const _StopwatchLap({required this.total, required this.split});

  final Duration total;
  final Duration split;
}

class _SplitRank {
  const _SplitRank({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class StopwatchScreen extends StatefulWidget {
  const StopwatchScreen({
    super.key,
    required this.appMenu,
    this.navigationDrawer,
    this.useInternalNavigationDrawer = true,
  });

  final Widget appMenu;
  final Widget? navigationDrawer;
  final bool useInternalNavigationDrawer;

  @override
  State<StopwatchScreen> createState() => _StopwatchScreenState();
}

class _StopwatchScreenState extends State<StopwatchScreen> {
  static const _storageKey = 'stopwatchState';

  Duration _accumulated = Duration.zero;
  DateTime? _runningSince;
  final List<_StopwatchLap> _laps = [];
  final ValueNotifier<Duration> _elapsed = ValueNotifier(Duration.zero);
  Timer? _ticker;
  bool _tickerModeEnabled = true;
  bool _userChangedState = false;

  bool get _isRunning => _runningSince != null;
  Duration get _currentElapsed => _runningSince == null
      ? _accumulated
      : _accumulated + DateTime.now().difference(_runningSince!);
  bool get _hasElapsed => _currentElapsed > Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadState();
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
      _elapsed.value = _currentElapsed;
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _elapsed.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(_storageKey);
      if (encoded == null || _userChangedState || !mounted) {
        return;
      }
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final runningSinceMs = decoded['runningSinceMs'] as int?;
      final laps = (decoded['laps'] as List<dynamic>? ?? const [])
          .map((item) {
            final lap = item as Map<String, dynamic>;
            return _StopwatchLap(
              total: Duration(milliseconds: lap['totalMs'] as int),
              split: Duration(milliseconds: lap['splitMs'] as int),
            );
          })
          .toList();
      setState(() {
        _accumulated = Duration(
          milliseconds: decoded['accumulatedMs'] as int? ?? 0,
        );
        _runningSince = runningSinceMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(runningSinceMs);
        _laps
          ..clear()
          ..addAll(laps);
      });
      _elapsed.value = _currentElapsed;
      _syncTicker();
    } catch (error) {
      developer.log('Stopwatch state could not be restored', error: error);
    }
  }

  Future<void> _persist() async {
    final encoded = jsonEncode({
      'accumulatedMs': _accumulated.inMilliseconds,
      'runningSinceMs': _runningSince?.millisecondsSinceEpoch,
      'laps': [
        for (final lap in _laps)
          {
            'totalMs': lap.total.inMilliseconds,
            'splitMs': lap.split.inMilliseconds,
          },
      ],
    });
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_storageKey, encoded);
    } catch (error) {
      developer.log('Stopwatch state could not be saved', error: error);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not save stopwatch progress.')),
      );
    }
  }

  void _start() {
    _userChangedState = true;
    _runningSince = DateTime.now();
    _elapsed.value = _currentElapsed;
    _syncTicker();
    setState(() {});
    unawaited(_persist());
  }

  void _pause() {
    _userChangedState = true;
    _accumulated = _currentElapsed;
    _runningSince = null;
    _elapsed.value = _accumulated;
    _syncTicker();
    setState(() {});
    unawaited(_persist());
  }

  _SplitRank? _splitRank(_StopwatchLap lap) {
    if (_laps.length < 2) {
      return null;
    }
    final splits = _laps.map((l) => l.split);
    final fastest = splits.reduce((a, b) => a < b ? a : b);
    final slowest = splits.reduce((a, b) => a > b ? a : b);
    if (fastest == slowest) {
      return null;
    }
    if (lap.split == fastest) {
      return const _SplitRank(label: 'Fastest', icon: Icons.bolt);
    }
    if (lap.split == slowest) {
      return const _SplitRank(label: 'Slowest', icon: Icons.hourglass_bottom);
    }
    return null;
  }

  void _lap() {
    if (!_hasElapsed) {
      return;
    }
    _userChangedState = true;
    final total = _currentElapsed;
    final previousTotal = _laps.isEmpty ? Duration.zero : _laps.first.total;
    _laps.insert(
      0,
      _StopwatchLap(total: total, split: total - previousTotal),
    );
    setState(() {});
    unawaited(_persist());
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset stopwatch?'),
        content: const Text('This clears the elapsed time and all laps.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('stopwatch-reset-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _reset();
    }
  }

  void _reset() {
    _userChangedState = true;
    _accumulated = Duration.zero;
    _runningSince = null;
    _laps.clear();
    _elapsed.value = Duration.zero;
    _syncTicker();
    setState(() {});
    unawaited(_persist());
  }

  void _syncTicker() {
    if (_isRunning && _tickerModeEnabled) {
      _ticker ??= Timer.periodic(const Duration(milliseconds: 30), (_) {
        _elapsed.value = _currentElapsed;
      });
      return;
    }
    _ticker?.cancel();
    _ticker = null;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final hundredths = (duration.inMilliseconds % 1000 ~/ 10)
        .toString()
        .padLeft(2, '0');
    return '$hours:$minutes:$seconds.$hundredths';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      drawer: widget.useInternalNavigationDrawer
          ? widget.navigationDrawer
          : null,
      appBar: AppBar(
        title: const Text('Stopwatch'),
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
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: SizedBox(
                            width: double.infinity,
                            child: ValueListenableBuilder<Duration>(
                              valueListenable: _elapsed,
                              builder: (context, elapsed, _) => Semantics(
                                label:
                                    'Elapsed time ${_formatDuration(elapsed)}',
                                liveRegion: true,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _formatDuration(elapsed),
                                    key: const ValueKey('stopwatch-display'),
                                    style: theme.textTheme.displayMedium
                                        ?.copyWith(
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                          fontWeight: FontWeight.w300,
                                          color: colorScheme.onSurface,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_laps.isEmpty && !_isRunning && !_hasElapsed) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Press start to time a run. Laps you record will appear here.',
                        key: const ValueKey('stopwatch-empty-hint'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (_laps.isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Laps', style: theme.textTheme.titleMedium),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 180,
                        child: ListView.separated(
                          key: const ValueKey('stopwatch-laps'),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _laps.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final lap = _laps[index];
                            final rank = _splitRank(lap);
                            return ListTile(
                              dense: true,
                              title: Text('Lap ${_laps.length - index}'),
                              subtitle: Text(
                                rank == null
                                    ? 'Total ${_formatDuration(lap.total)}'
                                    : '${rank.label} · Total ${_formatDuration(lap.total)}',
                              ),
                              leading: rank == null
                                  ? null
                                  : Icon(rank.icon, size: 20),
                              trailing: Text(
                                _formatDuration(lap.split),
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('stopwatch-secondary-action'),
                      onPressed: _hasElapsed ? _lap : null,
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('Lap'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('stopwatch-reset-action'),
                      onPressed: _hasElapsed ? _confirmReset : null,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('stopwatch-primary-action'),
                      onPressed: _isRunning ? _pause : _start,
                      icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow),
                      label: Text(_isRunning ? 'Pause' : 'Start'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
