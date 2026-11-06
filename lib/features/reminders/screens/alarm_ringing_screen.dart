import 'package:flutter/material.dart';

import '../../../services/notification_service.dart';
import '../models/reminder.dart';

class AlarmRingingScreen extends StatefulWidget {
  const AlarmRingingScreen({required this.reminder, super.key});

  final Reminder reminder;

  @override
  State<AlarmRingingScreen> createState() => _AlarmRingingScreenState();
}

class _AlarmRingingScreenState extends State<AlarmRingingScreen> {
  bool _responding = false;

  Future<void> _respond({required bool snooze}) async {
    if (_responding) {
      return;
    }

    setState(() => _responding = true);
    try {
      if (snooze) {
        await NotificationService.instance.snoozeAlarm(widget.reminder.id);
      } else {
        await NotificationService.instance.stopAlarm(widget.reminder.id);
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on Exception {
      if (mounted) {
        setState(() => _responding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to update this alarm.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(widget.reminder.dateTime));
    final description = widget.reminder.description?.trim();
    final snoozeDuration = _formatSnoozeDuration(
      widget.reminder.snoozeDurationMinutes,
    );

    return PopScope<void>(
      canPop: _responding,
      child: Scaffold(
        backgroundColor: colors.surface,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 620;
              return Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.alarm_rounded,
                          color: colors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 9),
                        Text(
                          'ALARM',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.2,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      width: compact ? 76 : 92,
                      height: compact ? 76 : 92,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.notifications_active_rounded,
                        color: colors.onPrimaryContainer,
                        size: compact ? 36 : 44,
                      ),
                    ),
                    SizedBox(height: compact ? 22 : 30),
                    Text(
                      time,
                      textAlign: TextAlign.center,
                      style:
                          (compact
                                  ? theme.textTheme.displaySmall
                                  : theme.textTheme.displayMedium)
                              ?.copyWith(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w300,
                                letterSpacing: -1.5,
                                fontFeatures: const [],
                              ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      widget.reminder.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (description != null && description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        description,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      'If unanswered, this alarm snoozes automatically after '
                      '5 minutes, then rings again in $snoozeDuration.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _responding
                                ? null
                                : () => _respond(snooze: false),
                            icon: const Icon(Icons.stop_rounded),
                            label: const Text('Stop'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(58),
                              shape: const StadiumBorder(),
                              textStyle: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _responding
                                ? null
                                : () => _respond(snooze: true),
                            icon: const Icon(Icons.snooze_rounded),
                            label: Text(
                              'Snooze · ${_formatSnoozeDuration(widget.reminder.snoozeDurationMinutes, abbreviated: true)}',
                            ),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(58),
                              foregroundColor: colors.onSurface,
                              side: BorderSide(color: colors.outline),
                              shape: const StadiumBorder(),
                              textStyle: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _formatSnoozeDuration(int minutes, {bool abbreviated = false}) {
    if (minutes >= 60 && minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      return abbreviated
          ? '$hours ${hours == 1 ? 'hr' : 'hrs'}'
          : '$hours ${hours == 1 ? 'hour' : 'hours'}';
    }
    return abbreviated
        ? '$minutes min'
        : '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
  }
}
