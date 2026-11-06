import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../auth/widgets/google_account_section.dart';
import '../calender/models/calendar_view_mode.dart';
import '../../services/notification_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_design_tokens.dart';
import '../../theme/app_color_themes.dart';
import '../reminders/models/reminder.dart';
import '../../theme/app_theme.dart';
import 'services/reminder_preferences_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.selectedThemeMode,
    required this.selectedCalendarViewMode,
    required this.onThemeModeChanged,
    required this.onCalendarViewModeChanged,
    this.selectedAccentColor = defaultAccentColor,
    this.onAccentColorChanged,
    this.preferencesStore,
    this.navigationDrawer,
  });

  final ThemeMode selectedThemeMode;
  final CalendarViewMode selectedCalendarViewMode;
  final Future<void> Function(ThemeMode) onThemeModeChanged;
  final Future<void> Function(CalendarViewMode) onCalendarViewModeChanged;
  final Color selectedAccentColor;
  final Future<void> Function(Color)? onAccentColorChanged;
  final ReminderPreferencesStore? preferencesStore;
  final Widget? navigationDrawer;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final ReminderPreferencesStore _preferencesStore;
  late Color _selectedAccentColor;
  ReminderDefaults _defaults = const ReminderDefaults();
  List<ReminderSoundOption> _availableSounds = const [];
  Future<void> _saveQueue = Future<void>.value();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedAccentColor = widget.selectedAccentColor;
    _preferencesStore =
        widget.preferencesStore ?? const ReminderPreferencesStore();
    _loadDefaults();
    _loadSounds();
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedAccentColor != widget.selectedAccentColor) {
      _selectedAccentColor = widget.selectedAccentColor;
    }
  }

  Future<void> _loadDefaults() async {
    try {
      final defaults = await _preferencesStore.loadDefaults();
      if (mounted) {
        setState(() {
          _defaults = defaults;
          _isLoading = false;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSaveError();
      }
    }
  }

  Future<void> _loadSounds() async {
    try {
      final sounds = await NotificationService.instance.availableAlarmSounds();
      if (mounted) {
        setState(() => _availableSounds = sounds);
      }
    } on Exception {
      if (mounted) {
        setState(() => _availableSounds = const []);
      }
    }
  }

  Future<void> _updateDefaults(ReminderDefaults defaults) async {
    setState(() => _defaults = defaults);
    final save = _saveQueue.then(
      (_) => _preferencesStore.saveDefaults(defaults),
    );
    _saveQueue = save.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    try {
      await save;
    } on Exception {
      if (mounted) {
        _showSaveError();
      }
    }
  }

  void _showSaveError() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Unable to save settings.')));
  }

  Future<void> _selectSound() async {
    final sounds = [
      const ReminderSoundOption(name: 'Default', uri: null),
      ..._availableSounds,
    ];
    final selection = await showModalBottomSheet<ReminderSoundOption>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              'Default ringtone',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final sound in sounds)
            ListTile(
              leading: Icon(
                _defaults.soundUri == sound.uri &&
                        _defaults.soundName == sound.name
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(sound.name),
              onTap: () => Navigator.of(context).pop(sound),
            ),
          if (_availableSounds.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text('No additional ringtones are available.'),
            ),
        ],
      ),
    );
    if (selection != null && mounted) {
      await _updateDefaults(
        _defaults.copyWith(
          soundUri: selection.uri,
          clearSoundUri: selection.uri == null,
          soundName: selection.name,
        ),
      );
    }
  }

  Future<void> _changeThemeMode(ThemeMode themeMode) async {
    try {
      await widget.onThemeModeChanged(themeMode);
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to save the theme setting.')),
        );
      }
    }
  }

  Future<void> _selectAccentColor() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AccentColorPickerDialog(
        initialColor: _selectedAccentColor,
        onColorChanged: (color) => unawaited(_changeAccentColor(color)),
      ),
    );
  }

  Future<void> _selectColorTheme() async {
    final selectedColor = await showDialog<Color>(
      context: context,
      builder: (_) =>
          _ColorThemePickerDialog(selectedColor: _selectedAccentColor),
    );
    if (selectedColor != null) {
      await _changeAccentColor(selectedColor);
    }
  }

  Future<void> _changeAccentColor(Color accentColor) async {
    if (_selectedAccentColor == accentColor) {
      return;
    }

    setState(() => _selectedAccentColor = accentColor);
    try {
      await widget.onAccentColorChanged?.call(accentColor);
    } on Exception {
      if (mounted) {
        _showSaveError();
      }
    }
  }

  Future<void> _changeCalendarViewMode(CalendarViewMode mode) async {
    if (_defaults.calendarViewMode == mode) {
      return;
    }

    await _updateDefaults(_defaults.copyWith(calendarViewMode: mode));
    try {
      await widget.onCalendarViewModeChanged(mode);
    } on Exception {
      if (mounted) {
        _showSaveError();
      }
    }
  }

  Widget? _navigationLeading(BuildContext context) {
    if (widget.navigationDrawer == null) return null;
    return SizedBox(
      width: 104,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Builder(
            builder: (context) => IconButton(
              key: const ValueKey('global-navigation-button'),
              tooltip: 'Open navigation menu',
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
          ),
          if (Navigator.of(context).canPop())
            IconButton(
              key: const ValueKey('settings-back-button'),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        drawer: widget.navigationDrawer,
        appBar: AppBar(
          leadingWidth: widget.navigationDrawer == null ? null : 104,
          title: const Text('Settings'),
          leading: _navigationLeading(context),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      drawer: widget.navigationDrawer,
      appBar: AppBar(
        leadingWidth: widget.navigationDrawer == null ? null : 104,
        title: const Text('Settings'),
        leading: _navigationLeading(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          const GoogleAccountSection(),
          _SettingsSection(
            title: 'Appearance',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                child: Text(
                  'Theme',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_outlined),
                      label: Text('System'),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Light'),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Dark'),
                    ),
                  ],
                  selected: {widget.selectedThemeMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    _changeThemeMode(selection.first);
                  },
                ),
              ),
              const _SettingsDivider(),
              _SettingsTile(
                key: const ValueKey('settings-color-theme-picker'),
                icon: Icons.palette_outlined,
                title: 'Color theme',
                subtitle: 'Preset palettes that set the app accent',
                trailing: _ColorThemePreview(color: _selectedAccentColor),
                onTap: _selectColorTheme,
              ),
              const _SettingsDivider(),
              _SettingsTile(
                key: const ValueKey('settings-accent-color-picker'),
                icon: Icons.color_lens_outlined,
                title: 'Custom accent color',
                subtitle: 'Pick any color with the wheel or hex code',
                trailing: _AccentColorIndicator(color: _selectedAccentColor),
                onTap: _selectAccentColor,
              ),
            ],
          ),
          _SettingsSection(
            title: 'Calendar',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                child: Text(
                  'Default calendar view',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Wrap(
                  key: const ValueKey('settings-calendar-view-mode'),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final mode in CalendarViewMode.values)
                      ChoiceChip(
                        label: Text(_calendarViewLabel(mode)),
                        selected: _defaults.calendarViewMode == mode,
                        onSelected: (_) => _changeCalendarViewMode(mode),
                      ),
                  ],
                ),
              ),
            ],
          ),
          _SettingsSection(
            title: 'Notifications',
            children: [
              _SettingsTile(
                key: const ValueKey('settings-default-notification'),
                icon: Icons.notifications_outlined,
                title: 'Default notification',
                subtitle: _notificationModeLabel(_defaults.notificationMode),
                onTap: _selectNotificationMode,
              ),
              const _SettingsDivider(),
              _SettingsTile(
                key: const ValueKey('settings-default-ringtone'),
                icon: Icons.music_note_outlined,
                title: 'Default ringtone',
                subtitle: _defaults.soundName,
                onTap: _selectSound,
              ),
              const _SettingsDivider(),
              _SettingsSwitchTile(
                key: const ValueKey('settings-default-vibration'),
                icon: Icons.vibration_outlined,
                title: 'Vibration',
                subtitle: _defaults.vibrate ? 'On' : 'Off',
                value: _defaults.vibrate,
                onChanged: (value) =>
                    _updateDefaults(_defaults.copyWith(vibrate: value)),
              ),
            ],
          ),
          _SettingsSection(
            title: 'Alarms',
            children: [
              _SettingsTile(
                key: const ValueKey('settings-default-snooze'),
                icon: Icons.snooze_outlined,
                title: 'Snooze duration',
                subtitle: _snoozeLabel(_defaults.snoozeDurationMinutes),
                onTap: _selectSnoozeDuration,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _selectSnoozeDuration() async {
    final selection = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              'Default snooze duration',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final minutes in _snoozeOptions)
            ListTile(
              key: ValueKey('snooze-default-$minutes'),
              leading: Icon(
                _defaults.snoozeDurationMinutes == minutes
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(_snoozeLabel(minutes)),
              onTap: () => Navigator.of(context).pop(minutes),
            ),
        ],
      ),
    );
    if (selection != null &&
        mounted &&
        selection != _defaults.snoozeDurationMinutes) {
      await _updateDefaults(
        _defaults.copyWith(snoozeDurationMinutes: selection),
      );
    }
  }

  Future<void> _selectNotificationMode() async {
    final selection = await showModalBottomSheet<ReminderNotificationMode>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              'Default notification',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final mode in ReminderNotificationMode.values)
            ListTile(
              key: ValueKey('notification-default-${mode.name}'),
              leading: Icon(
                _defaults.notificationMode == mode
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(_notificationModeLabel(mode)),
              onTap: () => Navigator.of(context).pop(mode),
            ),
        ],
      ),
    );
    if (selection != null &&
        mounted &&
        selection != _defaults.notificationMode) {
      await _updateDefaults(_defaults.copyWith(notificationMode: selection));
    }
  }

  String _notificationModeLabel(ReminderNotificationMode mode) => switch (mode) {
    ReminderNotificationMode.alarmAndNotification => 'Alarm + Notification',
    ReminderNotificationMode.notificationOnly => 'Notification only',
  };

  static const _snoozeOptions = <int>[5, 10, 15, 30, 60];

  String _snoozeLabel(int minutes) {
    if (minutes >= 60 && minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    return '$minutes minutes';
  }

  String _calendarViewLabel(CalendarViewMode mode) => switch (mode) {
    CalendarViewMode.threeDay => '3 Day',
    CalendarViewMode.year => 'Year',
    CalendarViewMode.month => 'Month',
    CalendarViewMode.week => 'Week',
    CalendarViewMode.day => 'Day',
    CalendarViewMode.list => 'List',
  };
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    indent: 56,
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      minVerticalPadding: 12,
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 32,
        child: Icon(icon, size: 22, color: colorScheme.onSurfaceVariant),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing:
          trailing ??
          Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant, size: 22),
      onTap: onTap,
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, size: 22, color: colorScheme.onSurfaceVariant),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _AccentColorIndicator extends StatelessWidget {
  const _AccentColorIndicator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outlineVariant;
    return AnimatedContainer(
      duration: AppMotion.resolve(context, AppMotion.interaction),
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: outline),
      ),
    );
  }
}

class _ColorThemePreview extends StatelessWidget {
  const _ColorThemePreview({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(seedColor: color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final value in [colors.primary, colors.secondary, colors.tertiary])
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(
              color: value,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _ColorThemePickerDialog extends StatelessWidget {
  const _ColorThemePickerDialog({required this.selectedColor});

  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Color theme'),
      contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      content: SizedBox(
        width: 360,
        height: math.min(MediaQuery.sizeOf(context).height * 0.5, 400),
        child: ListView(
          children: [
            for (final colorTheme in appColorThemes)
              Semantics(
                button: true,
                selected: selectedColor == colorTheme.primary,
                label:
                    '${colorTheme.name} color theme'
                    '${selectedColor == colorTheme.primary ? ', selected' : ''}',
                child: ListTile(
                  key: ValueKey('color-theme-${colorTheme.name.toLowerCase()}'),
                  leading: _ColorThemePreview(color: colorTheme.primary),
                  title: Text(colorTheme.name),
                  trailing: selectedColor == colorTheme.primary
                      ? Icon(Icons.check_circle, color: colorScheme.primary)
                      : null,
                  onTap: () => Navigator.of(context).pop(colorTheme.primary),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _AccentColorPickerDialog extends StatefulWidget {
  const _AccentColorPickerDialog({
    required this.initialColor,
    required this.onColorChanged,
  });

  final Color initialColor;
  final ValueChanged<Color> onColorChanged;

  @override
  State<_AccentColorPickerDialog> createState() =>
      _AccentColorPickerDialogState();
}

class _AccentColorPickerDialogState extends State<_AccentColorPickerDialog> {
  static const List<Color> _presetColors = [
    Color(0xFF4773FA),
    Color(0xFF008CFF),
    Color(0xFF00A896),
    Color(0xFF7B61FF),
    Color(0xFFE55381),
    Color(0xFFE47732),
    Color(0xFF65717D),
    Color(0xFFB28B00),
  ];

  late HSLColor _selectedColor;
  late final TextEditingController _hexController;
  String? _hexErrorText;

  @override
  void initState() {
    super.initState();
    _selectedColor = HSLColor.fromColor(widget.initialColor);
    _hexController = TextEditingController(
      text: _formatHex(widget.initialColor),
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color get _color => _selectedColor.toColor();

  String get _hexColor {
    return _formatHex(_color);
  }

  static String _formatHex(Color color) {
    final argb = color.toARGB32();
    final alpha = (argb >> 24) & 0xFF;
    final value = alpha == 255 ? argb & 0x00FFFFFF : argb;
    return '#${value.toRadixString(16).padLeft(alpha == 255 ? 6 : 8, '0').toUpperCase()}';
  }

  void _selectColor(Color color) {
    setState(() {
      _selectedColor = HSLColor.fromColor(color);
      _hexErrorText = null;
      _hexController.value = TextEditingValue(
        text: _formatHex(color),
        selection: TextSelection.collapsed(offset: _formatHex(color).length),
      );
    });
    widget.onColorChanged(color);
  }

  void _handleHexChanged(String input) {
    final normalized = input.trim().replaceFirst(RegExp(r'^#'), '');
    final isValidLength = normalized.length == 6 || normalized.length == 8;
    final value = isValidLength ? int.tryParse(normalized, radix: 16) : null;
    if (value == null) {
      setState(() {
        _hexErrorText = input.isEmpty
            ? null
            : 'Enter 6 or 8 hexadecimal digits.';
      });
      return;
    }

    final color = normalized.length == 6
        ? Color(0xFF000000 | value)
        : Color(value);
    setState(() {
      _selectedColor = HSLColor.fromColor(color);
      _hexErrorText = null;
    });
    widget.onColorChanged(color);
  }

  void _updateWheel(Offset position, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final offset = position - center;
    final radius = math.min(size.width, size.height) / 2;
    final distance = math.min(offset.distance / radius, 1.0);
    final hue = (math.atan2(offset.dy, offset.dx) * 180 / math.pi + 360) % 360;
    _selectColor(
      _selectedColor.withHue(hue).withSaturation(distance).toColor(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final wheelSide = math.min(
      248.0,
      math.max(160.0, MediaQuery.sizeOf(context).width - 96),
    );
    return AlertDialog(
      title: const Text('Choose accent color'),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: 'Accent color preview $_hexColor',
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    color: AppColors.highContrastForeground(_color),
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Presets',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var index = 0; index < _presetColors.length; index++)
                    _buildPresetSwatch(index, _presetColors[index]),
                ],
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Color wheel',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Semantics(
                  label: 'Color wheel',
                  value: _hexColor,
                  hint: 'Touch and drag to choose hue and saturation',
                  child: SizedBox.square(
                    dimension: wheelSide,
                    child: Builder(
                      builder: (context) {
                        final size = Size.square(wheelSide);
                        final hueRadians = _selectedColor.hue * math.pi / 180;
                        final center = Offset(size.width / 2, size.height / 2);
                        final radius = wheelSide / 2;
                        final indicator =
                            center +
                            Offset(math.cos(hueRadians), math.sin(hueRadians)) *
                                (radius * _selectedColor.saturation);
                        return GestureDetector(
                          key: const ValueKey('accent-color-wheel'),
                          onPanDown: (details) =>
                              _updateWheel(details.localPosition, size),
                          onPanUpdate: (details) =>
                              _updateWheel(details.localPosition, size),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _ColorWheelPainter(),
                                ),
                              ),
                              Positioned(
                                left: indicator.dx - 13,
                                top: indicator.dy - 13,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: _color,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surface,
                                        width: 3,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.shadow.withValues(
                                            alpha: 0.45,
                                          ),
                                          blurRadius: 3,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildSlider(
                label: 'Brightness',
                value: _selectedColor.lightness,
                min: 0,
                max: 1,
                divisions: 100,
                valueLabel: '${(_selectedColor.lightness * 100).round()}%',
                sliderKey: const ValueKey('accent-lightness-slider'),
                onChanged: (value) =>
                    _selectColor(_selectedColor.withLightness(value).toColor()),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('accent-hex-input'),
                controller: _hexController,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'HEX color',
                  hintText: '#008CFF',
                  errorText: _hexErrorText,
                  prefixIcon: const Icon(Icons.tag),
                ),
                onChanged: _handleHexChanged,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _selectColor(widget.initialColor);
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _buildPresetSwatch(int index, Color color) {
    final selected = color.toARGB32() == _color.toARGB32();
    return Semantics(
      button: true,
      selected: selected,
      label: 'Preset color ${_formatHex(color)}',
      child: InkResponse(
        key: ValueKey('accent-preset-$index'),
        onTap: () => _selectColor(color),
        radius: 28,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.outline
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  color: AppColors.highContrastForeground(color),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueLabel,
    required Key sliderKey,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(valueLabel, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        Semantics(
          label: label,
          child: Slider(
            key: sliderKey,
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final center = bounds.center;
    final radius = math.min(size.width, size.height) / 2;
    final circle = Rect.fromCircle(center: center, radius: radius);
    canvas.save();
    canvas.clipPath(Path()..addOval(circle));
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ],
        ).createShader(circle),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Colors.white, Color(0x00FFFFFF)],
        ).createShader(circle),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) => false;
}
