import 'package:app_smarana/features/calender/calender_screen.dart';
import 'package:app_smarana/features/calender/models/calendar_view_mode.dart';
import 'package:app_smarana/features/calender/widgets/calendar_view_selector.dart';
import 'package:app_smarana/features/reminders/models/reminder.dart';
import 'package:app_smarana/features/reminders/services/reminder_storage.dart';
import 'package:app_smarana/theme/app_design_tokens.dart';
import 'package:app_smarana/theme/premium_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DateTime now;
  late _TestReminderStorage storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 9, 29, 0, 5);
    storage = _TestReminderStorage([
      _reminder(
        id: 'weekly',
        title: 'Weekly reminder',
        dateTime: DateTime(2026, 9, 28, 9),
        type: RecurrenceType.weekly,
        dayOfWeek: DateTime.friday,
      ),
      _reminder(
        id: 'tomorrow',
        title: 'Tomorrow reminder',
        dateTime: DateTime(2026, 9, 30, 10),
      ),
    ]);
  });

  testWidgets('shows the full month grid and selected date by default', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);

    expect(find.text('September'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-view-month')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-view-selector')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('calendar-month-grid'))).height,
      greaterThan(250),
    );
    expect(
      find.byKey(const ValueKey('calendar-countdown-sheet')),
      findsNothing,
    );
    final monthGrid = tester.widget<GridView>(
      find.byKey(const ValueKey('calendar-month-grid')),
    );
    expect(monthGrid.childrenDelegate.estimatedChildCount, 42);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('calendar-day-2026-9-29')),
          )
          .properties
          .selected,
      isTrue,
    );
  });

  testWidgets('selected date fills its cell and today keeps an outline', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);
    final colors = Theme.of(
      tester.element(find.byKey(const ValueKey('calendar-day-cell-2026-9-29'))),
    ).colorScheme;

    AnimatedContainer dateCell(String key) =>
        tester.widget<AnimatedContainer>(find.byKey(ValueKey(key)));

    final todayDecoration =
        dateCell('calendar-day-cell-2026-9-29').decoration! as BoxDecoration;
    expect(todayDecoration.color, colors.primary);
    expect(todayDecoration.border!.top.color, colors.onPrimary);

    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-9-30')));
    await _pumpFrames(tester);

    final selectedDecoration =
        dateCell('calendar-day-cell-2026-9-30').decoration! as BoxDecoration;
    expect(selectedDecoration.color, colors.primary);
    expect(selectedDecoration.border, isNull);
    final todayAfterSelection =
        dateCell('calendar-day-cell-2026-9-29').decoration! as BoxDecoration;
    expect(
      todayAfterSelection.color,
      colors.primaryContainer.withValues(alpha: 0.2),
    );
    expect(todayAfterSelection.border!.top.color, colors.primary);
  });

  testWidgets('renders the month layout when selected', (tester) async {
    await _pumpCalendar(
      tester,
      () => now,
      storage,
      viewMode: CalendarViewMode.month,
    );

    expect(find.byKey(const ValueKey('calendar-view-month')), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
  });

  testWidgets('renders daily and weekly reminders on the Calendar', (
    tester,
  ) async {
    final visibilityStorage = _TestReminderStorage([
      _reminder(
        id: 'daily',
        title: 'Daily reminder',
        dateTime: DateTime(2026, 9, 28, 9),
        type: RecurrenceType.daily,
      ),
      _reminder(
        id: 'weekly',
        title: 'Weekly reminder',
        dateTime: DateTime(2026, 9, 28, 9),
        type: RecurrenceType.weekly,
        dayOfWeek: DateTime.friday,
      ),
    ]);
    await _pumpCalendar(tester, () => now, visibilityStorage);

    expect(find.text('Daily reminder'), findsOneWidget);
    expect(find.text('Weekly reminder'), findsNothing);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('calendar-day-2026-10-2')),
          )
          .properties
          .label,
      contains('2 reminders'),
    );
  });

  testWidgets('month cells summarize many reminders in a capped event area', (
    tester,
  ) async {
    final crowdedDayStorage = _TestReminderStorage([
      for (var index = 0; index < 10; index++)
        _reminder(
          id: 'crowded-$index',
          title: 'Crowded reminder $index',
          dateTime: DateTime(2026, 9, 30, index + 5),
        ),
    ]);
    await _pumpCalendar(tester, () => now, crowdedDayStorage);

    final dayCell = find.byKey(const ValueKey('calendar-day-2026-9-30'));
    final eventArea = find.byKey(
      const ValueKey('calendar-month-event-area-2026-9-30'),
    );
    expect(
      find.byKey(const ValueKey('calendar-month-event-count-10')),
      findsOneWidget,
    );
    expect(find.text('Crowded reminder 0'), findsNothing);
    expect(
      tester.getSize(eventArea).height,
      lessThanOrEqualTo(tester.getSize(dayCell).height * 0.2 + 1),
    );

    await tester.tap(dayCell);
    await _pumpFrames(tester);
    expect(find.byKey(const ValueKey('calendar-view-month')), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('calendar-selected-day-count')),
          )
          .data,
      '10 reminders',
    );
    expect(find.text('05:00'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('14:00'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('calendar-selected-day-events')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('14:00'), findsOneWidget);

    await tester.tap(find.text('Crowded reminder 9'));
    await _pumpFrames(tester);
    expect(find.byKey(const ValueKey('title-field')), findsOneWidget);
  });

  testWidgets('day view shows an empty state without an hourly timeline', (
    tester,
  ) async {
    await _pumpCalendar(
      tester,
      () => now,
      _TestReminderStorage(const []),
      viewMode: CalendarViewMode.day,
    );

    expect(find.text('No reminders'), findsWidgets);
    expect(find.text('00:00'), findsNothing);
    expect(find.byKey(const ValueKey('calendar-day-event-list')), findsNothing);
  });

  testWidgets('month grid has no surface while list grid keeps its surface', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);

    final monthSurface = find.ancestor(
      of: find.byKey(const ValueKey('calendar-month-grid')),
      matching: find.byType(PremiumSurface),
    );
    expect(monthSurface, findsNothing);

    await tester.tap(find.byKey(const ValueKey('calendar-view-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();

    final list = tester.widget<PremiumSurface>(
      find.ancestor(
        of: find.byKey(const ValueKey('calendar-month-grid')),
        matching: find.byType(PremiumSurface),
      ),
    );
    expect(list.color, isNull);
    expect(list.borderColor, isNull);
    expect(list.radius, AppRadius.section);
    expect(list.elevation, AppElevation.subtle);
  });

  testWidgets('view selector switches to 3 Day and keeps selected date', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);
    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-9-30')));
    await _pumpFrames(tester);

    await tester.tap(find.byKey(const ValueKey('calendar-view-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 Day'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('calendar-view-threeDay')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calendar-timeline-threeDay')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('calendar-timeline-date-2026-9-30')),
          )
          .properties
          .selected,
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.text('Tomorrow reminder'),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('calendar-timeline-threeDay')),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    expect(find.text('Tomorrow reminder'), findsOneWidget);
  });

  testWidgets('month and week date selection stays in its view', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);

    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-9-30')));
    await _pumpFrames(tester);
    expect(find.byKey(const ValueKey('calendar-view-month')), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('calendar-selected-day-count')),
          )
          .data,
      '1 reminder',
    );
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('Tomorrow reminder'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calendar-view-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Day'));
    await _pumpFrames(tester);
    expect(find.byKey(const ValueKey('calendar-view-day')), findsOneWidget);

    final septemberThirtieth = find.byKey(
      const ValueKey('calendar-timeline-date-2026-9-30'),
    );
    await tester.tap(find.byTooltip('Back to Week'));
    await _pumpFrames(tester);
    await tester.tap(septemberThirtieth);
    await _pumpFrames(tester);
    expect(find.byKey(const ValueKey('calendar-view-week')), findsOneWidget);
    expect(
      tester.widget<Semantics>(septemberThirtieth).properties.selected,
      isTrue,
    );

    await tester.tap(find.byTooltip('Back to Month'));
    await _pumpFrames(tester);
    expect(find.byKey(const ValueKey('calendar-view-month')), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('calendar-day-2026-9-30')),
          )
          .properties
          .selected,
      isTrue,
    );
  });

  testWidgets('view menu has six ordered options and marks Month selected', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);
    await tester.tap(find.byKey(const ValueKey('calendar-view-selector')));
    await tester.pumpAndSettle();

    const labels = ['List', 'Year', 'Month', 'Week', '3 Day', 'Day'];
    final positions = [
      for (final label in labels) tester.getTopLeft(find.text(label)).dy,
    ];
    expect(positions, orderedEquals([...positions]..sort()));
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('calendar-view-option-month')),
          )
          .properties
          .selected,
      isTrue,
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('year, list, week and day views render', (tester) async {
    await _pumpCalendar(tester, () => now, storage);

    for (final entry in [
      (CalendarViewMode.year, 'calendar-view-year'),
      (CalendarViewMode.list, 'calendar-view-list'),
      (CalendarViewMode.week, 'calendar-view-week'),
      (CalendarViewMode.day, 'calendar-view-day'),
    ]) {
      await tester.tap(find.byKey(const ValueKey('calendar-view-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.$1.label));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey(entry.$2)), findsOneWidget);
      if (entry.$1 == CalendarViewMode.year) {
        expect(find.text('2026'), findsOneWidget);
        final octoberDate = find.byKey(
          const ValueKey('calendar-day-2026-10-2'),
        );
        await tester.scrollUntilVisible(
          octoberDate,
          250,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('calendar-view-year')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(
          tester.widget<Semantics>(octoberDate).properties.label,
          contains('1 reminder'),
        );
      }
    }
  });

  testWidgets('list keeps the calendar fixed while its agenda scrolls', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);
    await tester.tap(find.byKey(const ValueKey('calendar-view-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();

    final grid = find.byKey(const ValueKey('calendar-month-grid'));
    final agenda = find.byKey(const ValueKey('calendar-list-content'));
    expect(grid, findsOneWidget);
    expect(find.text('Upcoming Events'), findsOneWidget);
    expect(find.text('Weekly reminder'), findsWidgets);
    final gridTop = tester.getTopLeft(grid).dy;

    await tester.drag(agenda, const Offset(0, -400));
    await tester.pumpAndSettle();

    final scrollable = find.descendant(
      of: agenda,
      matching: find.byType(Scrollable),
    );
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      greaterThan(0),
    );
    expect(tester.getTopLeft(grid).dy, closeTo(gridTop, 0.1));
  });

  testWidgets('upcoming list excludes daily recurrence and shows countdowns', (
    tester,
  ) async {
    final upcomingStorage = _TestReminderStorage([
      _reminder(
        id: 'daily-countdown',
        title: 'Daily countdown',
        dateTime: DateTime(2026, 9, 28, 9),
        type: RecurrenceType.daily,
      ),
      _reminder(
        id: 'weekly-countdown',
        title: 'Weekly countdown',
        dateTime: DateTime(2026, 9, 28, 9),
        type: RecurrenceType.weekly,
        dayOfWeek: DateTime.friday,
      ),
      _reminder(
        id: 'tomorrow-countdown',
        title: 'Tomorrow countdown',
        dateTime: DateTime(2026, 9, 30, 10),
      ),
    ]);
    await _pumpCalendar(
      tester,
      () => now,
      upcomingStorage,
      viewMode: CalendarViewMode.list,
    );

    final list = find.byKey(const ValueKey('calendar-list-content'));
    expect(
      find.descendant(of: list, matching: find.text('Daily countdown')),
      findsNothing,
    );
    expect(
      find.descendant(of: list, matching: find.text('Weekly countdown')),
      findsWidgets,
    );
    expect(
      find.descendant(of: list, matching: find.text('Tomorrow countdown')),
      findsOneWidget,
    );
    expect(find.text('In 3 days'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
  });

  testWidgets('week view shows each date and its own stacked events', (
    tester,
  ) async {
    final weekStorage = _TestReminderStorage([
      _reminder(
        id: 'tuesday-event',
        title: 'Tuesday event',
        dateTime: DateTime(2026, 9, 29, 9),
      ),
      _reminder(
        id: 'wednesday-event',
        title: 'Wednesday event',
        dateTime: DateTime(2026, 9, 30, 10),
      ),
      _reminder(
        id: 'wednesday-event-later',
        title: 'Wednesday later',
        dateTime: DateTime(2026, 9, 30, 15),
      ),
    ]);
    await _pumpCalendar(
      tester,
      () => now,
      weekStorage,
      viewMode: CalendarViewMode.week,
    );

    for (final date in [
      DateTime(2026, 9, 28),
      DateTime(2026, 9, 29),
      DateTime(2026, 9, 30),
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 2),
      DateTime(2026, 10, 3),
      DateTime(2026, 10, 4),
    ]) {
      expect(
        find.byKey(
          ValueKey(
            'calendar-timeline-date-${date.year}-${date.month}-${date.day}',
          ),
        ),
        findsOneWidget,
      );
    }

    final tuesday = find.byKey(
      const ValueKey('calendar-week-events-2026-9-29'),
    );
    final wednesday = find.byKey(
      const ValueKey('calendar-week-events-2026-9-30'),
    );
    expect(
      find.descendant(of: tuesday, matching: find.text('Tuesday event')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: wednesday, matching: find.text('Wednesday event')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: wednesday, matching: find.text('Wednesday later')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tuesday, matching: find.text('Wednesday event')),
      findsNothing,
    );
  });

  testWidgets('week navigation and swipes preserve selected weekday', (
    tester,
  ) async {
    await _pumpCalendar(
      tester,
      () => now,
      storage,
      viewMode: CalendarViewMode.week,
    );
    await tester.tap(find.byKey(const ValueKey('calendar-next-week')));
    await _pumpFrames(tester);
    expect(
      find.byKey(const ValueKey('calendar-timeline-date-2026-10-6')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const ValueKey('calendar-week-swipe-region')),
      const Offset(-160, 0),
    );
    await _pumpFrames(tester);
    expect(
      find.byKey(const ValueKey('calendar-timeline-date-2026-10-13')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('calendar-week-today')));
    await _pumpFrames(tester);
    expect(
      find.byKey(const ValueKey('calendar-timeline-date-2026-9-29')),
      findsOneWidget,
    );
  });

  testWidgets('week layout fits a small dark-mode screen', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: CalendarScreen(
          storage: storage,
          clock: () => now,
          viewMode: CalendarViewMode.week,
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byKey(const ValueKey('calendar-view-week')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final dateCell = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('calendar-week-date-cell-2026-9-29')),
    );
    final decoration = dateCell.decoration! as BoxDecoration;
    final colors = Theme.of(
      tester.element(
        find.byKey(const ValueKey('calendar-week-date-cell-2026-9-29')),
      ),
    ).colorScheme;
    expect(decoration.color, colors.primary);
    expect(decoration.border!.top.color, colors.onPrimary);
  });

  testWidgets('list slides months in the navigation direction', (tester) async {
    await _pumpCalendar(tester, () => now, storage);
    await tester.tap(find.byKey(const ValueKey('calendar-view-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();

    const septemberKey = ValueKey('calendar-list-month-2026-9');
    const octoberKey = ValueKey('calendar-list-month-2026-10');
    final september = find.byKey(septemberKey);
    Offset slideOffset(Finder month) {
      final positions = tester
          .widgetList<SlideTransition>(
            find.ancestor(of: month, matching: find.byType(SlideTransition)),
          )
          .map((transition) => transition.position.value);
      return positions.firstWhere(
        (position) => position.dx != 0,
        orElse: () => Offset.zero,
      );
    }

    await tester.tap(find.byTooltip('More calendar views'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next month'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final october = find.byKey(octoberKey);
    expect(september, findsOneWidget);
    expect(october, findsOneWidget);
    expect(slideOffset(september).dx, lessThan(0));
    expect(slideOffset(october).dx, greaterThan(0));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More calendar views'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Previous month'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(october, findsOneWidget);
    expect(september, findsOneWidget);
    expect(slideOffset(october).dx, greaterThan(0));
    expect(slideOffset(september).dx, lessThan(0));
  });

  testWidgets('year view selects a date and opens its detailed month', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);
    await tester.tap(find.byKey(const ValueKey('calendar-view-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();

    expect(find.text('2026'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-year-month-2026-1')),
      findsOneWidget,
    );
    final selectedMarker = tester.getCenter(
      find.byKey(const ValueKey('calendar-day-marker-2026-9-29')),
    );
    final selectedNumber = tester.getCenter(
      find.byKey(const ValueKey('calendar-day-number-2026-9-29')),
    );
    expect(selectedNumber.dx, closeTo(selectedMarker.dx, 0.1));
    expect(selectedNumber.dy, closeTo(selectedMarker.dy, 0.1));

    final octoberNinth = find.byKey(const ValueKey('calendar-day-2026-10-9'));
    await tester.scrollUntilVisible(
      octoberNinth,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('calendar-view-year')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(octoberNinth);
    await _pumpFrames(tester);

    expect(find.byKey(const ValueKey('calendar-view-year')), findsOneWidget);
    expect(tester.widget<Semantics>(octoberNinth).properties.selected, isTrue);
    expect(
      tester.widget<Semantics>(octoberNinth).properties.label,
      contains('1 reminder'),
    );

    await tester.tap(find.byKey(const ValueKey('calendar-year-month-2026-10')));
    await _pumpFrames(tester);

    expect(find.byKey(const ValueKey('calendar-view-month')), findsOneWidget);
    expect(find.text('October'), findsOneWidget);
    expect(tester.widget<Semantics>(octoberNinth).properties.selected, isTrue);
  });

  testWidgets('year navigation changes year and preserves selection', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);
    await tester.tap(find.byKey(const ValueKey('calendar-view-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More calendar views'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next year'));
    await _pumpFrames(tester);

    expect(find.text('2027'), findsOneWidget);
    final selectedDate = find.byKey(const ValueKey('calendar-day-2027-9-29'));
    await tester.scrollUntilVisible(
      selectedDate,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('calendar-view-year')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.widget<Semantics>(selectedDate).properties.selected, isTrue);

    await tester.tap(find.byTooltip('More calendar views'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next year'));
    await _pumpFrames(tester);

    final leapDay = find.byKey(const ValueKey('calendar-day-2028-2-29'));
    await tester.scrollUntilVisible(
      leapDay,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('calendar-view-year')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      tester.widget<Semantics>(leapDay).properties.label,
      contains('February 29, 2028'),
    );
  });

  testWidgets('year picker selects a year directly from the centered dialog', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);
    await tester.tap(find.byKey(const ValueKey('calendar-view-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('calendar-select-date')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-year-picker')), findsOneWidget);
    expect(find.text('Select year'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Select'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('calendar-year-option-2027')));
    await _pumpFrames(tester);

    expect(find.byType(Dialog), findsNothing);
    expect(find.text('2027'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('calendar-day-2027-9-29')),
          )
          .properties
          .selected,
      isTrue,
    );
  });

  testWidgets('vertical year scrolling springs back without changing year', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);
    await tester.tap(find.byKey(const ValueKey('calendar-view-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('calendar-view-year')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026'), findsOneWidget);
    expect(find.text('2027'), findsNothing);
  });

  testWidgets('entering year view keeps the currently displayed year', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);

    await tester.tap(find.byKey(const ValueKey('calendar-select-date')));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(DatePickerDialog)))
        .pop(DateTime(2027, 10, 2));
    await _pumpFrames(tester);

    await tester.tap(find.byKey(const ValueKey('calendar-view-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();

    expect(find.text('2027'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('calendar-day-2027-10-2')),
          )
          .properties
          .selected,
      isTrue,
    );
  });

  testWidgets('month view shows the empty state for a free selected day', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);

    expect(find.byKey(const ValueKey('calendar-empty-day')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-selected-day-events')),
      findsNothing,
    );
    expect(find.text('You have a free day'), findsOneWidget);
    expect(find.text('Take it easy'), findsOneWidget);
  });

  testWidgets('month content scrolls on a short viewport', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;

    await _pumpCalendar(tester, () => now, storage);

    final monthView = find.byKey(const ValueKey('calendar-view-month'));
    expect(monthView, findsOneWidget);
    final scrollable = find
        .descendant(of: monthView, matching: find.byType(Scrollable))
        .first;
    expect(
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
      greaterThan(0),
    );
  });

  testWidgets('navigates between months and returns to today', (tester) async {
    await _pumpCalendar(tester, () => now, storage);

    expect(find.text('September'), findsOneWidget);
    await tester.tap(find.byTooltip('More calendar views'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next month'));
    await _pumpFrames(tester);
    expect(find.text('October'), findsOneWidget);

    await tester.tap(find.byTooltip('More calendar views'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Previous month'));
    await _pumpFrames(tester);
    expect(find.text('September'), findsOneWidget);

    await tester.tap(find.byTooltip('More calendar views'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to Today'));
    await _pumpFrames(tester);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('calendar-day-2026-9-29')),
          )
          .properties
          .selected,
      isTrue,
    );
  });

  testWidgets('date selection updates the agenda and selects one date', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);

    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-9-30')));
    await _pumpFrames(tester);

    expect(find.byKey(const ValueKey('calendar-view-month')), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('calendar-day-2026-9-30')),
          )
          .properties
          .selected,
      isTrue,
    );
    expect(find.text('Tomorrow reminder'), findsOneWidget);
  });

  testWidgets('swiping the month grid advances the displayed month', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);

    await tester.drag(
      find.byKey(const ValueKey('calendar-month-grid')),
      const Offset(-260, 0),
    );
    await _pumpFrames(tester);

    expect(find.text('October'), findsOneWidget);
  });

  for (final viewMode in [CalendarViewMode.month, CalendarViewMode.list]) {
    testWidgets(
      '${viewMode.name} fast flick navigates below distance threshold',
      (tester) async {
        await _pumpCalendar(tester, () => now, storage, viewMode: viewMode);
        final grid = find.byKey(const ValueKey('calendar-month-grid'));
        final isHorizontal = viewMode == CalendarViewMode.month;

        await tester.timedDrag(
          grid,
          isHorizontal ? const Offset(-30, 0) : const Offset(0, -30),
          const Duration(milliseconds: 20),
          frequency: 200,
        );
        await tester.pumpAndSettle();

        expect(find.text('October'), findsOneWidget);
      },
    );

    testWidgets(
      '${viewMode.name} swipe cancels below threshold and supports vertical navigation',
      (tester) async {
        await _pumpCalendar(tester, () => now, storage, viewMode: viewMode);
        final grid = find.byKey(const ValueKey('calendar-month-grid'));
        final size = tester.getSize(grid);

        await tester.drag(grid, Offset(-size.width * 0.20, 0));
        await tester.pumpAndSettle();
        expect(find.text('September'), findsOneWidget);

        await tester.drag(grid, Offset(0, -size.height * 0.15));
        await tester.pumpAndSettle();
        expect(find.text('September'), findsOneWidget);

        await tester.drag(grid, Offset(0, -size.height * 0.21));
        await tester.pumpAndSettle();
        expect(find.text('October'), findsOneWidget);

        final nextGrid = find.byKey(const ValueKey('calendar-month-grid'));
        await tester.drag(nextGrid, Offset(0, size.height * 0.21));
        await tester.pumpAndSettle();
        expect(find.text('September'), findsOneWidget);
      },
    );

    testWidgets('${viewMode.name} swipe locks navigation while settling', (
      tester,
    ) async {
      await _pumpCalendar(tester, () => now, storage, viewMode: viewMode);
      final grid = find.byKey(const ValueKey('calendar-month-grid'));
      final width = tester.getSize(grid).width;

      await tester.timedDrag(
        grid,
        Offset(-width * 0.35, 0),
        const Duration(milliseconds: 100),
      );
      await tester.pump(const Duration(milliseconds: 30));
      await tester.drag(
        find.byKey(const ValueKey('calendar-month-swipe-region')),
        Offset(-width * 0.35, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('October'), findsOneWidget);
      expect(find.text('November 2026'), findsNothing);
    });
  }

  for (final viewMode in [CalendarViewMode.month, CalendarViewMode.list]) {
    testWidgets('${viewMode.name} swipe slides months in the swipe direction', (
      tester,
    ) async {
      await _pumpCalendar(tester, () => now, storage, viewMode: viewMode);

      final grid = find.byKey(const ValueKey('calendar-month-grid'));
      final septemberKey = viewMode == CalendarViewMode.list
          ? const ValueKey('calendar-list-month-2026-9')
          : const ValueKey('calendar-month-2026-9');
      final octoberKey = viewMode == CalendarViewMode.list
          ? const ValueKey('calendar-list-month-2026-10')
          : const ValueKey('calendar-month-2026-10');
      final september = find.byKey(septemberKey);
      final october = find.byKey(octoberKey);

      Offset slideOffset(Finder month) {
        final positions = tester
            .widgetList<SlideTransition>(
              find.ancestor(of: month, matching: find.byType(SlideTransition)),
            )
            .map((transition) => transition.position.value);
        return positions.firstWhere(
          (position) => position.dx != 0,
          orElse: () => Offset.zero,
        );
      }

      await tester.timedDrag(
        grid,
        const Offset(-260, 0),
        const Duration(milliseconds: 100),
      );
      await tester.pump(const Duration(milliseconds: 120));

      expect(september, findsOneWidget);
      expect(october, findsOneWidget);
      expect(slideOffset(september).dx, lessThan(0));
      expect(slideOffset(october).dx, greaterThan(0));
      await tester.pumpAndSettle();

      await tester.timedDrag(
        grid,
        const Offset(260, 0),
        const Duration(milliseconds: 100),
      );
      await tester.pump(const Duration(milliseconds: 120));

      expect(september, findsOneWidget);
      expect(october, findsOneWidget);
      expect(slideOffset(october).dx, greaterThan(0));
      expect(slideOffset(september).dx, lessThan(0));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('List Countdown opens a draggable, scrollable sheet', (
    tester,
  ) async {
    final countdownReminders = List.generate(
      12,
      (index) => _reminder(
        id: 'countdown-$index',
        title: 'Countdown reminder $index',
        dateTime: DateTime(2026, 10, index + 1, 9),
      ),
    );
    await _pumpCalendar(
      tester,
      () => now,
      _TestReminderStorage(countdownReminders),
    );

    await tester.tap(find.byKey(const ValueKey('calendar-view-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-countdown-toggle')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('calendar-countdown-sheet')),
      findsOneWidget,
    );
    final content = find.byKey(const ValueKey('calendar-countdown-content'));
    final collapsedHeight = tester.getSize(content).height;
    await tester.drag(content, const Offset(0, -220));
    await tester.pumpAndSettle();
    final expandedHeight = tester.getSize(content).height;
    expect(expandedHeight, greaterThan(collapsedHeight));
    final countdownScrollable = find.descendant(
      of: content,
      matching: find.byType(Scrollable),
    );
    expect(
      tester
          .state<ScrollableState>(countdownScrollable)
          .position
          .maxScrollExtent,
      greaterThan(0),
    );

    await tester.drag(content, const Offset(0, 220));
    await tester.pumpAndSettle();
    expect(tester.getSize(content).height, lessThan(expandedHeight));
  });

  testWidgets('month heading opens date picker', (tester) async {
    await _pumpCalendar(tester, () => now, storage);

    await tester.tap(find.byKey(const ValueKey('calendar-select-date')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);

    Navigator.of(tester.element(find.byType(DatePickerDialog)))
        .pop(DateTime(2027, 9, 29));
    await _pumpFrames(tester);

    expect(find.text('September'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('calendar-day-2027-9-29')),
          )
          .properties
          .selected,
      isTrue,
    );
  });

  testWidgets('tapping a month date shows its selected-day agenda', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);

    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-9-30')));
    await _pumpFrames(tester);

    expect(find.byKey(const ValueKey('calendar-view-month')), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('calendar-selected-day-count')),
          )
          .data,
      '1 reminder',
    );
    expect(find.text('10:00'), findsOneWidget);
  });

  testWidgets(
    'month date selects its agenda and list date opens week on double tap',
    (tester) async {
      await _pumpCalendar(tester, () => now, storage);

      final monthDate = find.byKey(const ValueKey('calendar-day-2026-9-30'));
      await tester.tap(monthDate);
      await _pumpFrames(tester);
      expect(find.byKey(const ValueKey('calendar-view-month')), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('calendar-selected-day-count')),
            )
            .data,
        '1 reminder',
      );
      await tester.tap(find.byKey(const ValueKey('calendar-view-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Day'));
      await _pumpFrames(tester);
      expect(find.byKey(const ValueKey('calendar-view-day')), findsOneWidget);
      await tester.tap(find.byTooltip('Back to Week'));
      await _pumpFrames(tester);
      expect(find.byKey(const ValueKey('calendar-view-week')), findsOneWidget);
      await tester.tap(find.byTooltip('Back to Month'));
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const ValueKey('calendar-view-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();

      final listDate = find.byKey(const ValueKey('calendar-day-2026-9-30'));
      await tester.tap(listDate);
      await _pumpFrames(tester);
      expect(find.byKey(const ValueKey('calendar-view-list')), findsOneWidget);
      expect(tester.widget<Semantics>(listDate).properties.selected, isTrue);

      await _doubleTap(tester, listDate);
      await _pumpFrames(tester);
      expect(find.byKey(const ValueKey('calendar-view-week')), findsOneWidget);
    },
  );

  testWidgets('selects adjacent month dates and opens them in day view', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);

    final octoberFirst = find.byKey(const ValueKey('calendar-day-2026-10-1'));
    await tester.tap(octoberFirst);
    await _pumpFrames(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-view-month')), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('calendar-day-2026-10-1')),
          )
          .properties
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('calendar-day-2026-10-1')),
          )
          .properties
          .selected,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('calendar-view-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Day'));
    await _pumpFrames(tester);
    expect(find.byKey(const ValueKey('calendar-view-day')), findsOneWidget);
    await tester.tap(find.byTooltip('Back to Week'));
    await _pumpFrames(tester);
    await tester.tap(find.byTooltip('Back to Month'));
    await _pumpFrames(tester);
    await tester.tap(find.byTooltip('More calendar views'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Previous month'));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-8-31')));
    await _pumpFrames(tester);
    expect(find.text('August'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-view-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Day'));
    await _pumpFrames(tester);
    expect(find.byKey(const ValueKey('calendar-view-day')), findsOneWidget);
  });

  testWidgets('calendar add action prepopulates the selected date', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);
    final addButton = tester.widget<FloatingActionButton>(
      find.ancestor(
        of: find.byTooltip('Add reminder for selected date'),
        matching: find.byType(FloatingActionButton),
      ),
    );
    expect(addButton.shape, isA<CircleBorder>());
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-9-30')));
    await _pumpFrames(tester);
    await tester.tap(find.byTooltip('Add reminder for selected date'));
    await _pumpFrames(tester);

    final dateField = find.byKey(const ValueKey('date-field'));
    final expectedDate = MaterialLocalizations.of(tester.element(dateField))
        .formatMediumDate(DateTime(2026, 9, 30));
    expect(
      find.descendant(of: dateField, matching: find.text(expectedDate)),
      findsOneWidget,
    );
  });

  testWidgets('creates, edits, and deletes reminders from the calendar', (
    tester,
  ) async {
    await _pumpCalendar(tester, () => now, storage);
    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-9-30')));
    await _pumpFrames(tester);
    await tester.tap(find.byTooltip('Add reminder for selected date'));
    await _pumpFrames(tester);
    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'Created from calendar',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('save-reminder')));
    await tester.tap(find.byKey(const ValueKey('save-reminder')));
    await _pumpFrames(tester);
    await _pumpFrames(tester);
    expect(storage.reminders, hasLength(3));

    final createdReminder = storage.reminders.singleWhere(
      (reminder) => reminder.title == 'Created from calendar',
    );
    await tester.tap(find.byKey(const ValueKey('calendar-view-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    final createdTitle = find.descendant(
      of: find.byKey(const ValueKey('calendar-list-content')),
      matching: find.text('Created from calendar'),
    );
    expect(createdTitle, findsOneWidget);
    await tester.ensureVisible(createdTitle);
    await tester.tap(createdTitle);
    await _pumpFrames(tester);
    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'Edited in calendar',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('save-reminder')));
    await tester.tap(find.byKey(const ValueKey('save-reminder')));
    await _pumpFrames(tester);
    await _pumpFrames(tester);
    expect(
      storage.reminders
          .singleWhere((reminder) => reminder.id == createdReminder.id)
          .title,
      'Edited in calendar',
    );

    await tester.tap(find.byTooltip('More actions for Edited in calendar'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Delete'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Delete').last);
    await _pumpFrames(tester);
    await _pumpFrames(tester);
    expect(
      storage.reminders.any((reminder) => reminder.id == createdReminder.id),
      isFalse,
    );
  });
}

Future<void> _pumpCalendar(
  WidgetTester tester,
  DateTime Function() clock,
  ReminderStorage storage, {
  CalendarViewMode viewMode = CalendarViewMode.month,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CalendarScreen(storage: storage, clock: clock, viewMode: viewMode),
    ),
  );
  await _pumpFrames(tester);
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder);
}

Reminder _reminder({
  required String id,
  required String title,
  required DateTime dateTime,
  RecurrenceType type = RecurrenceType.none,
  int? dayOfWeek,
}) {
  return Reminder(
    id: id,
    title: title,
    dateTime: dateTime,
    recurrenceRule: RecurrenceRule(type: type, dayOfWeek: dayOfWeek),
    createdAt: DateTime(2026),
  );
}

class _TestReminderStorage extends ReminderStorage {
  _TestReminderStorage(this.reminders);

  final List<Reminder> reminders;

  @override
  Future<List<Reminder>> getReminders() async => List.of(reminders);

  @override
  Future<void> addReminder(Reminder reminder) async {
    reminders.add(reminder);
  }

  @override
  Future<void> updateReminder(Reminder reminder) async {
    final index = reminders.indexWhere((item) => item.id == reminder.id);
    if (index != -1) {
      reminders[index] = reminder;
    }
  }

  @override
  Future<void> deleteReminder(String id) async {
    reminders.removeWhere((reminder) => reminder.id == id);
  }
}
