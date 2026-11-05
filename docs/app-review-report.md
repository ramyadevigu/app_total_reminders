# Total Reminders — Application Review Report

**Scope:** Full static review of the Flutter application under `lib/`, with focus on navigation, Timer, Stopwatch, Settings, reminder defaults, and notification/alarm wiring. Calendar, Notes, and Reminders were scanned for structure, dialogs, menus, and error handling; a line-by-line pass of those large screens is listed as a follow-up task (T-40).

**Design references:** Google Keep (Notes), Google Clock (Timer, Stopwatch, Alarms), Google Settings (Settings). Inspiration only; Total Reminders keeps its own identity.

**Baseline:** `flutter analyze` reports no issues. The test suite (27 files) has not been run as part of this review.

**Working tree note:** Several Notes and test files already had uncommitted changes before this review. They were not modified.

---

## 1. Executive Summary

Total Reminders has a solid foundation: a deadline-based timer, a centralized theme with color themes, a notification action pipeline with snooze, a native alarm path, and a clean `flutter analyze`. The main gaps are functional rather than cosmetic:

1. **Timers do not alert the user when they finish.** There is no sound, vibration, or notification. This is the largest gap against Google Clock.
2. **Timers do not survive restart in running state.** Only the duration is saved.
3. **Settings contains a snooze control that does nothing.** The value is hard-coded to 15 minutes at load, and the default is never applied to new reminders.
4. **Navigation is inconsistent.** My Day is reachable only from the drawer, the bottom bar highlights the wrong tab, and the drawer header is mislabeled "Profile" while Profile is also listed as the first tile.
5. **Design system is not yet applied consistently.** Dozens of hard-coded colors remain in feature screens, and Settings uses ad-hoc section and tile widgets instead of a Google Settings-style grouped list.

The recommended path is to fix reliability and functional gaps first (Critical/High), then bring Timer, Stopwatch, Notes, and Settings up to the reference apps, then polish animation and the design system.

---

## 2. Screen-by-Screen Assessment

### 2.1 App Shell and Navigation (`lib/app/app.dart`, `lib/widgets/app_navigation_drawer.dart`)

| Area | Observation | Rating |
|---|---|---|
| Bottom NavigationBar | 5 destinations: Calendar, Notes, Alarms, Stopwatch, Timer. Tabs are kept in an `IndexedStack` and built lazily on first visit. `TickerMode` pauses inactive tabs. | Good |
| My Day | Not in the bottom bar. Reachable only via the drawer. | High issue |
| Selected state | While My Day is displayed, the bar still highlights the previous tab (`selectedIndex: _currentIndex`). | High issue |
| Drawer header | Labelled "Profile" with an `event_note_rounded` icon. Icon and label do not match. | Medium issue |
| Drawer duplication | "Profile" appears as the header and again as the first tile. | Medium issue |
| Signed-out Profile tile | Tap does nothing when `GoogleAuthService.instance.currentUser` is null. No message, no sign-in prompt. | High issue |
| Search | Opens a modal dialog and then switches tabs. Notes has no inline search. | Medium issue |
| Help dialog | Copy describes Alarms and Calendar generically and does not explain My Day, Notes, or Timer. | Low issue |
| Send Feedback | Shows "Feedback delivery is not configured yet." SnackBar. Visible placeholder in a shipped build. | Medium issue |
| Drawer rebuilds | `_buildTab` and drawer/menu widgets are rebuilt on every shell build. | Low (performance) |
| Notification and alarm routing | Duplicate guards use flags and a pending ID in `_openReminderFromNotification` and `_openRingingAlarm`. | Good |

### 2.2 Calendar (`lib/features/calender/calender_screen.dart`, about 108 KB)

- Contains a year picker dialog, delete confirmation, a reminder detail sheet, and PopupMenu actions.
- Scan shows 13 hard-coded `Colors.` or `Color(0x` uses. These should move to the theme or to a centralized calendar color resolver.
- Calendar view mode is shared with Settings through `calendarViewMode`. Legacy `nextThreeDays` and `threeDay` values are mapped.
- **Not yet reviewed line by line:** month grid behavior, swipe transitions, Next 3 Days overlap layout, and Month Only overflow. These are listed as follow-up work.

### 2.3 My Day (`lib/features/my_day/my_day_screen.dart`)

- Calls `NotificationService.instance.previewAlarmSound` on sound preview.
- Contains 7 `mounted`/async-gap references and 1 hard-coded color.
- The screen is the intended planning anchor per `docs/designs/connected-productivity-mvp.md`, but it is not a bottom-bar destination (see 2.1).

### 2.4 Notes (`lib/features/notes/`)

- Screens: `notes_screen.dart`, `notebook_detail_screen.dart`, `all_notes_screen.dart`, `rich_note_editor_screen.dart` (about 85 KB), plus widgets such as `recent_note_card.dart`, `notebook_list_tile.dart`, `note_tag_chip.dart`, `notebook_selector.dart`, `note_editor_action_sheets.dart`, `notes_home_quick_create_menu.dart`, and `note_table_embed_builder.dart`.
- Features present: notebooks, tags, sorting (`_NotesSortOrder`), project status, duplication, reminder linkage, attachments, and a Quill-based rich editor with table embeds.
- Persistence failures show SnackBars ("Notes could not be saved."), but restore and index failures only call `debugPrint`, so the user gets no feedback.
- `notes_screen.dart` contains 3 hard-coded colors; `rich_note_editor_screen.dart` contains 14.
- Search lives in a modal dialog rather than inline on the notes list (Keep uses an inline search bar with filter chips).
- **Not yet reviewed line by line:** editor toolbar layout, title placement (spec requires title beside back button, default "Untitled"), and card visuals against Keep. These are listed as follow-up work.

### 2.5 Reminders and Add/Edit (`lib/features/reminders/`)

- `reminders_screen.dart` uses a `PopupMenuButton` per item, delete confirmation dialog, and SnackBars for failures.
- `add_reminder_screen.dart` (about 73 KB) reads notification mode, sound, and vibrate from `ReminderDefaults` on load (lines 128–136). It **does not read `snoozeDurationMinutes`** and initializes snooze to 15 at line 97.
- Custom snooze dialog (5/10/15 presets plus custom minutes/hours) is well built.
- `alarm_ringing_screen.dart` offers Snooze and Dismiss with clear labels. It shows the auto-snooze explanation text.
- Reminder model (`reminder.dart`) has JSON round-tripping with safe defaults for missing fields (`vibrate`, `snoozeDurationMinutes`), which is good for backward compatibility.

### 2.6 Timer (`lib/features/time_tools/timer_screen.dart`)

**Working:**
- Deadline-based countdown using a `DateTime` deadline and a 250 ms ticker, so the timer stays correct when the UI is paused or backgrounded.
- Pause, resume, restart, delete, progress ring.
- Setup keypad sheet with presets.
- Multiple saved timers in a list.

**Gaps:**
- Finishing a timer changes the card to red only. No sound, vibration, or notification.
- Running state is not persisted. Only `{id, seconds}` is saved under `savedTimers`. A running timer loses its deadline after restart.
- No user-entered labels. Titles are auto-generated (e.g., "1m 30s timer").
- `_persistSavedTimers()` is called with `unawaited`, so write failures are silent.
- Timer completion is not wired into `NotificationService`, so a timer cannot wake the device or alert when the app is closed.

### 2.7 Stopwatch (`lib/features/time_tools/stopwatch_screen.dart`)

**Working:** Start, pause, lap, reset. Reset is disabled when elapsed time is zero. A 30 ms ticker drives a `ValueNotifier`, so only the time label rebuilds.

**Gaps:**
- Lap rows show cumulative time only. Google Clock shows both lap (split) time and total.
- State is in memory only and is lost on app restart or process death.
- Lap button appears only while running, so a paused stopwatch cannot record a lap.
- No lap count or fastest/slowest lap highlight.

### 2.8 Settings (`lib/features/settings/settings_screen.dart`, `services/reminder_preferences_store.dart`)

**Sections:** Google account, Appearance (System/Light/Dark segmented control, Color theme dialog, Custom accent dialog with HSV/hex/slider), Calendar (default view chips), Notifications (Alarm+Notification vs Notification-only, default ringtone, vibration switch), Alarms (snooze).

**Defects:**
- **Snooze is not persisted or applied.** `loadDefaults()` hard-codes `snoozeDurationMinutes: 15` and never reads `_snoozeDurationKey`. `saveDefaults` writes the key, but nothing reads it back.
- The Snooze tile is a non-interactive `_SettingsTile` with a fixed "15 minutes" subtitle and no chevron. It looks editable but is not.
- Two overlapping color features exist (Color theme and Custom accent). Their relationship is unclear to the user.
- The leading area combines menu and back controls in a 104 px-wide slot, which crowds the title.

**Design gaps against Google Settings:**
- Sections use custom `_SettingsSection`/`_SettingsTile` widgets with no consistent icon column, row height, or divider rhythm.
- Subtitle headers for Theme and Calendar are ad hoc.
- Save failures show a SnackBar (good), but there is no inline state indicator for each setting.

### 2.9 Profile, Login, and Google Account (`lib/features/auth/`)

- `profile_screen.dart` has 3 `mounted`/async references and 0 hard-coded colors. Layout was not reviewed in detail.
- `login_screen.dart` has 4 hard-coded colors.
- `google_account_section.dart` is embedded in Settings.
- Drawer Profile tile is a no-op when signed out (see 2.1).
- **Not yet reviewed line by line:** sign-in error states, sign-out confirmation, and profile edit flow.

### 2.10 Notifications and Alarms (`lib/services/notification_service.dart`, `lib/services/*callback.dart`)

- Single notification service with a native alarm platform channel (`pendingSnoozeTime`, `snoozeAlarm`) and a fallback implementation.
- Notification actions handle `snooze` through `reminder_notification_action_callback.dart`, which uses the reminder's `snoozeDurationMinutes`.
- Recurring alarm callback clears expired `snoozedUntil` values.
- **Verify:** scheduled notifications for reminders call `_scheduleNotification` with `soundUri: null` (`notification_service.dart` around line 332). If this is the scheduling path for reminders, custom ringtones may not be applied to the notification. The Android channel fallback (`content://settings/system/alarm_alert`) is used when `soundUri` is null. This must be confirmed before changing it.

---

## 3. Functional Bugs

| ID | Bug | Location | Impact |
|---|---|---|---|
| B-01 | Snooze default from Settings is never loaded or saved correctly. Always 15 minutes. | `reminder_preferences_store.dart` (`loadDefaults`), `settings_screen.dart` (~425–435) | Settings promise is broken |
| B-02 | New reminders ignore the default snooze. | `add_reminder_screen.dart` lines 97, 128–136 | Settings value never applies |
| B-03 | Timer completion has no sound, vibration, or notification. | `timer_screen.dart` | Timer is not reliable as a timer |
| B-04 | Running timers lose deadline after restart. | `timer_screen.dart` (`savedTimers` persists only `{id, seconds}`) | Data loss of active state |
| B-05 | Timer persistence errors are not handled. | `timer_screen.dart` (`unawaited(_persistSavedTimers())`) | Silent failures |
| B-06 | My Day shows the previous bottom-bar tab as selected. | `app.dart` (`selectedIndex: _currentIndex`) | Misleading navigation state |
| B-07 | Drawer header label and icon are mislabeled; Profile is listed twice. | `app_navigation_drawer.dart` | Confusing navigation |
| B-08 | Profile tile is a silent no-op when signed out. | `app_navigation_drawer.dart` | Dead control |
| B-09 | Feedback placeholder shows in the shipped UI. | `app.dart` (~line 765) | Incomplete feature visible to users |
| B-10 | Notes restore/index failures are only logged; user is not informed. | `notes_screen.dart` (lines ~160, ~388) | Silent data issues |
| B-11 | Stopwatch laps show cumulative time only. | `stopwatch_screen.dart` | Missing core Clock behavior |
| B-12 | Stopwatch state is lost on restart. | `stopwatch_screen.dart` | Lost measurements |
| B-13 | Lap is available only while running. | `stopwatch_screen.dart` | Cannot lap while paused |
| B-14 | Help copy does not describe My Day, Notes, or Timer. | `app.dart` (Help dialog) | Misleading guidance |
| B-15 | Custom ringtone may not apply to scheduled reminder notifications (to verify). | `notification_service.dart` (~line 332) | Possible audible mismatch |

---

## 4. UI/UX Issues

| ID | Issue | Area |
|---|---|---|
| U-01 | Hard-coded colors across feature screens (about 130 matches in `lib/`): Calendar 13, Rich Note Editor 14, Settings 6, Notes list 3, Login 4, My Day 1, Add Reminder 3. | Design system |
| U-02 | `app_theme.dart` (28) and `app_colors.dart` (16) contain raw colors that are not all mapped to semantic roles. | Theme |
| U-03 | Settings does not follow a grouped-card, icon-column, consistent row-height pattern like Google Settings. | Settings |
| U-04 | Search is a modal dialog, not inline on Notes (Keep pattern). | Notes, navigation |
| U-05 | Timer cards do not show a clear completed state with an action (Stop / Restart / Dismiss). | Timer |
| U-06 | Stopwatch lacks a split/total dual display and lap highlighting. | Stopwatch |
| U-07 | Note card visuals and editor title placement are not yet verified against the spec (title beside back button, default "Untitled", floating toolbar). | Notes |
| U-08 | Drawer and tab transitions are not consistently animated (only the IndexedStack switch). | Animation |
| U-09 | Settings leading controls (menu + back) are crowded in a 104 px slot. | Settings |
| U-10 | Timer and Stopwatch tabs have no empty-state illustration or guidance text beyond the basic prompt. | Empty states |
| U-11 | Accessibility: important states (enabled/disabled, completed timer) must include icon or text, not color alone. Not yet audited across all screens. | Accessibility |

---

## 5. Performance Observations

| ID | Observation | Severity |
|---|---|---|
| P-01 | `_buildTab` and drawer widgets rebuild on every shell build. | Low |
| P-02 | Drawer notebook/note tree uses `FutureBuilder` over `NoteWorkspaceStorage` on each open. Results should be cached in state. | Medium |
| P-03 | Stopwatch ticker at 30 ms updates a `ValueNotifier`. Acceptable, but the label is the only rebuilt widget and should stay that way. | Info |
| P-04 | Timer ticker at 250 ms only runs while a timer is active (`_syncTicker`). Good. | Info |
| P-05 | Calendar (108 KB) and Rich Note Editor (85 KB) are large single-file screens. Expensive work in `build()` should be verified and split into widgets. | Medium (to verify) |
| P-06 | Recurrence and date conversions in Calendar should be memoized per month. Not yet verified. | Medium (to verify) |

---

## 6. Improvement Recommendations

1. **Timers as first-class alarms.** Route timer completion through `NotificationService` (sound, vibration, notification with Stop/Restart actions), and persist the deadline and running state.
2. **Stopwatch parity with Clock.** Show split and total, allow lap while paused, and persist the state.
3. **Settings as a grouped list.** Adopt a Google Settings-style layout: grouped cards, leading icons, consistent row height, and a chevron for every row that opens an editor. Remove the non-functional Snooze tile or make it live.
4. **Single source of truth for defaults.** Load and save every `ReminderDefaults` field, including snooze, and apply them to new reminders.
5. **Navigation clarity.** Make My Day a visible destination (or reflect its selection on the bar), fix the drawer header, remove the duplicate Profile item, and give a signed-out Profile tile a sign-in entry point.
6. **Notes parity with Keep.** Inline search with filter chips, card grid with pinned section, note color chips from the theme, a floating formatting toolbar, and title beside the back button.
7. **Design tokens.** Move feature-level colors to semantic roles in `lib/theme/`, keep calendar/event colors in one resolver, and keep Light, Dark, and System modes verified per screen.
8. **Motion.** Use one set of durations and curves (for example 200–300 ms, `Curves.easeOutCubic`) for route transitions, tab switches, sheet presentation, and selection feedback. Add subtle press feedback on cards and chips.
9. **Feedback and errors.** Replace placeholder feedback with a real or hidden entry point, and surface Notes and Timer persistence errors to the user.

---

## 7. Prioritized Task List

Priority: **Critical** (data loss, broken promised behavior, or user-facing failure), **High** (major UX gap or inconsistency with reference apps), **Medium** (polish and robustness), **Low** (cleanup).

| ID | Priority | Task | Addresses | Depends on |
|---|---|---|---|---|
| T-01 | Critical | Persist timer deadline and running state; restore on restart | B-04 | — |
| T-02 | Critical | Fire timer completion through `NotificationService` (sound, vibration, notification) | B-03 | T-01 |
| T-03 | Critical | Load and save snooze default; apply to new reminders; make Settings snooze tile editable | B-01, B-02 | — |
| T-04 | Critical | Verify and fix ringtone application for scheduled reminder notifications | B-15 | — |
| T-05 | High | Handle timer persistence errors and surface them | B-05 | T-01 |
| T-06 | High | Show My Day selected state correctly in the navigation bar, or make it a destination | B-06 | — |
| T-07 | High | Fix drawer header label/icon; remove duplicate Profile entry | B-07 | — |
| T-08 | High | Signed-out Profile tile opens sign-in or explains state | B-08 | — |
| T-09 | High | Replace Feedback placeholder with real flow or hide it | B-09 | — |
| T-10 | High | Stopwatch split and total laps; allow lap while paused | B-11, B-13 | — |
| T-11 | High | Persist Stopwatch state across restart | B-12 | — |
| T-12 | High | Timer completed state with Stop/Restart/Dismiss actions and clear non-color cues | U-05, U-11 | T-02 |
| T-13 | High | Rebuild Settings as a grouped list with icons, consistent rows, chevrons | U-03, U-09 | T-03 |
| T-14 | High | Notes inline search and filter chips (replace search dialog) | U-04 | — |
| T-15 | High | Notes editor: title beside back button, default "Untitled", floating toolbar | U-07 | — |
| T-16 | High | Surface Notes restore/save failures to the user | B-10 | — |
| T-17 | Medium | Update Help copy for all current destinations | B-14 | T-06 |
| T-18 | Medium | Cache drawer notebook/note tree instead of rebuilding `FutureBuilder` | P-02 | — |
| T-19 | Medium | Replace hard-coded colors in feature screens with theme roles or the calendar color resolver | U-01, U-02 | — |
| T-20 | Medium | Define a motion token set and apply to tabs, routes, sheets, and selection | U-08 | — |
| T-21 | Medium | Accessibility audit: non-color state cues, touch targets, text scale | U-11 | T-19 |
| T-22 | Medium | Empty states and guidance for Timer, Stopwatch, and Notes | U-10 | — |
| T-23 | Medium | Split large screens (Calendar, Rich Note Editor) into widgets; move work out of `build()` | P-05 | — |
| T-24 | Medium | Memoize calendar month recurrence results | P-06 | — |
| T-25 | Medium | Clarify Color theme vs Custom accent relationship in Settings | Settings 2.8 | T-13 |
| T-26 | Low | Reduce drawer and menu rebuilds in the app shell | P-01 | — |
| T-27 | Low | Replace `debugPrint` in Notes with the project logging approach | B-10 | T-16 |
| T-28 | Low | Timer labels entered by the user | Timer gap | T-01 |
| T-29 | Low | Stopwatch lap highlighting (fastest/slowest) | U-06 | T-10 |
| T-30 | Low | Consolidate Search entry points | Navigation | T-14 |
| T-40 | High | Line-by-line review of Calendar, Notes editor, and Add Reminder (follow-up of this report) | Review coverage | — |
| T-41 | High | Run `flutter test` and record baseline before changes | Quality | — |

---

## 8. Implementation Roadmap

**Phase 0 — Baseline (no behavior change)**
- T-41 (test baseline), T-40 (complete the deep review of the three large screens).

**Phase 1 — Reliability (Critical)**
- T-03, T-04 (defaults and ringtone correctness) — independent, can run in parallel with T-01.
- T-01 → T-02 (timer persistence, then completion alerts).
- T-05 after T-01.

**Phase 2 — Navigation and functional gaps (High)**
- T-06, T-07, T-08, T-09 — independent small changes.
- T-10, T-11 — Stopwatch.
- T-12 depends on T-02.
- T-16 — Notes error surfacing.

**Phase 3 — Reference-app parity (High)**
- T-13 (Settings) depends on T-03.
- T-14, T-15 (Notes Keep parity).

**Phase 4 — Design system and motion (Medium)**
- T-19 (tokens) → T-21 (accessibility audit).
- T-20 (motion tokens), T-22 (empty states), T-23 (screen splitting), T-24 (memoization).
- T-25 depends on T-13.

**Phase 5 — Polish (Low)**
- T-17 depends on T-06; T-18, T-26, T-27, T-28 (depends on T-01), T-29 (depends on T-10), T-30 (depends on T-14).

---

## 9. Acceptance Criteria

| Area | Criteria |
|---|---|
| Timer | Starting a timer, backgrounding or killing the app, and reopening it shows the correct remaining time. On completion, a sound, vibration, and notification fire even when the app is closed. Stop, restart, and dismiss work from the notification. |
| Stopwatch | Each lap shows split and total. Lap works while paused. State survives restart. Reset requires confirmation or is clearly undoable. |
| Settings | Every row is either a working control or is visibly non-interactive. Snooze default persists across restart and applies to new reminders. Grouped layout matches the Google Settings pattern in Light, Dark, and System modes. |
| Reminders | New reminder uses the saved snooze, sound, and vibrate defaults. Edited reminder keeps its own values. Scheduled notifications use the selected ringtone. |
| Navigation | The selected destination always matches the visible screen. Drawer labels match their icons. Each drawer item has one entry. Signed-out Profile leads to sign-in. No placeholder text is visible to users. |
| Notes | Inline search filters the list. Editor title defaults to "Untitled" and sits beside the back button. Save and restore failures are visible to the user. Cards are readable in Light and Dark. |
| Design system | No hard-coded colors in ordinary UI widgets. Theme and calendar colors come from the centralized theme or resolver. Light, Dark, and System are verified per screen. |
| Motion | Tab switches, route changes, and sheets use the shared motion tokens. No animation blocks input or scrolling. |
| Accessibility | Every state uses an icon or text in addition to color. Touch targets are at least 48 dp. Layouts remain usable at large text scale. |
| Performance | Month navigation, view switching, and Notes scrolling stay responsive. No expensive work runs in `build()`. |
| Quality | `flutter analyze` reports no issues. `flutter test` passes, with new tests for the timer restore, snooze default, and stopwatch lap behavior. |

---

## 10. Final Quality Checklist

- [ ] Timer state survives restart (T-01)
- [ ] Timer completion alerts with sound, vibration, and notification (T-02)
- [ ] Snooze default saves, loads, and applies to new reminders (T-03)
- [ ] Scheduled reminder ringtone verified (T-04)
- [ ] My Day selected state and navigation labels fixed (T-06, T-07)
- [ ] Profile signed-out path and Feedback placeholder resolved (T-08, T-09)
- [ ] Stopwatch split/total laps and persistence (T-10, T-11)
- [ ] Settings grouped layout and no dead controls (T-13)
- [ ] Notes inline search and editor title placement (T-14, T-15)
- [ ] Notes and Timer errors surfaced to the user (T-05, T-16)
- [ ] Hard-coded colors replaced in feature screens (T-19)
- [ ] Motion tokens applied (T-20)
- [ ] Accessibility audit complete (T-21)
- [ ] Calendar and Notes deep review completed (T-40)
- [ ] `flutter analyze` clean
- [ ] `flutter test` passing (T-41)
- [ ] Light, Dark, and System verified on every screen changed
- [ ] Existing reminder, recurrence, and notification behavior verified unchanged

---

## 11. Limitations of This Review

- Calendar, Notes editor, Reminders list, and Add/Edit Reminder were scanned for structure, dialogs, and hard-coded colors, not read line by line. Findings for those screens are provisional until T-40 is complete.
- The Profile and Login flows were not exercised on a device.
- No runtime or device testing was performed. Timer and notification behavior is based on code reading.
- The `flutter test` suite was not run.
