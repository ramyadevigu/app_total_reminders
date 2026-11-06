# Implementation Checklist — App Review Report

Source: [app-review-report.md](./app-review-report.md)

Legend: `[ ]` pending · `[~]` in progress · `[x]` implemented and verified · `[!]` blocked / deviation (see notes)

## Phase 0 — Baseline

- [x] T-41 Run `flutter analyze` and `flutter test`; record baseline (baseline: 193 tests passing, 0 analyzer issues)
- [ ] T-40 Line-by-line review of Calendar, Notes editor, Add Reminder

## Phase 1 — Reliability (Critical)

- [x] T-03 Snooze default: load/save/apply to new reminders; editable Snooze tile (B-01, B-02) — `reminder_settings_test.dart` 2/2 passing
- [x] T-04 Verify and fix ringtone for scheduled reminder notifications (B-15) — verified intentional: notification-only reminders never use the alarm tone (existing test "notification-only reminders never use the selected alarm sound"). Deviation: no change made. Custom tones still apply to alarm-mode reminders via the native alarm path. Needs device check.
- [x] T-01 Persist timer deadline and running state; restore on restart (B-04) — `timer_screen_test.dart` 4/4 passing (running restore, expired-as-finished, malformed skipped, persist on restart)
- [x] T-02 Timer completion via `NotificationService`: sound, vibration, notification (B-03) — depends on T-01. Added `showTimerFinished` to `NotificationPlatform` and `NotificationService`, wired through `TimerScreen.onTimerFinished` in `lib/app/app.dart`. Alerts fire only on live finishes, not on restore. Covered by widget tests and a service unit test. Needs device check for sound and vibration.
- [x] T-05 Timer persistence error handling (B-05) — `_persistAndReport` shows SnackBar on save failure. Failure path not yet covered by a test. Depends on T-01.

## Phase 2 — Navigation and functional gaps (High)

- [x] T-06 My Day selected state in navigation bar (B-06) — `NavigationBarTheme` clears the indicator and uses outline icons while My Day shows; covered in `app_navigation_drawer_test.dart`
- [x] T-07 Drawer header label/icon; remove duplicate Profile (B-07) — header now reads "Total Reminders"; covered in `app_navigation_drawer_test.dart`
- [x] T-08 Signed-out Profile tile opens sign-in (B-08) — pushes `LoginScreen` when no user is signed in (`app.dart`)
- [x] T-09 Replace Feedback placeholder (B-09) — "Send Feedback" removed from app menu and notes drawer; "Help" kept. Assertions in `widget_test.dart`. Deviation: the note editor's More menu still shows "Help and feedback are not available here yet." (`rich_note_editor_screen.dart`), which is out of scope for this task.
- [x] T-10 Stopwatch split + total laps; lap while paused (B-11, B-13) — `stopwatch_screen.dart`; covered in `stopwatch_screen_test.dart`
- [x] T-11 Stopwatch state persistence (B-12) — running state, laps, and elapsed time saved under `stopwatchState`; restore and malformed-data tests in `stopwatch_screen_test.dart`. Reset now asks for confirmation (AlertDialog, my choice of pattern).
- [x] T-12 Timer completed state with Stop/Restart/Dismiss and non-color cues (U-05, U-11) — depends on T-02. Verified: "Finished" text label + check icon, Restart and "Stop and dismiss" buttons; 8/8 timer tests pass.
- [x] T-16 Surface Notes save/restore failures (B-10). Verified: restore, save, and index failures show a MaterialBanner with Retry; new test "failed workspace restore shows a banner with retry"; notes tests 20/20 pass.

## Phase 3 — Reference-app parity (High)

- [x] T-13 Settings grouped list: icons, consistent rows, chevrons (U-03, U-09) — depends on T-03. Verified: "Default notification" is now a tile opening a bottom sheet; reminder_settings_test passes.
- [x] T-14 Notes inline search and filter chips (U-04). Verified: chip row (All notes / Archive / Deleted, plus removable label chip); new chip test in notes_screen_test passes; analyze clean.
- [x] T-15 Notes editor: title beside back button, default "Untitled", floating toolbar (U-07). Verified: title `TextField` (key `rich-note-title-field`) moved into the AppBar `title` beside the back button, hint "Untitled"; the floating toolbar already existed. Updated hint assertion in `rich_note_editor_screen_test.dart`; note tests 34/34 pass; analyze clean.

## Phase 4 — Design system and motion (Medium)

- [x] T-19 Replace hard-coded colors in feature screens with theme roles / resolver (U-01, U-02). Settings accent swatch border and shadow use theme roles. Deliberate literals kept: accent presets, color wheel, note palettes, Google brand colors, `Colors.transparent`. `flutter analyze` clean.
- [x] T-20 Motion token set applied to tabs, routes, sheets, selection (U-08). `FadeIndexedStack` cross-fades tabs (`lib/widgets/fade_indexed_stack.dart`); test `test/fade_indexed_stack_test.dart`. Theme test finders now use `hitTestable()` because inactive tabs stay mounted.
- [ ] T-21 Accessibility audit: non-color cues, 48 dp targets, text scale (U-11) — depends on T-19
- [x] T-22 Empty states for Timer, Stopwatch, Notes (U-10) — Timer already had `_EmptyTimersState`. Stopwatch shows a guidance hint on a fresh, idle stopwatch (`stopwatch-empty-hint`, test added). Notes already has guidance copy for every empty state (no notes, archive, label, search with no matches). Verified in review.
- [ ] T-23 Split large screens; move work out of `build()` (P-05)
- [x] T-24 Memoize calendar month recurrence results (P-06). Verified: `_refreshVisibleOccurrences` caches by reminders identity and visible range; full suite passes.
- [x] T-25 Clarify Color theme vs Custom accent in Settings — depends on T-13. Verified: subtitles reworded to describe presets vs custom picker; theme_system_test passes.

## Phase 5 — Polish (Low / Medium)

- [x] T-17 Update Help copy for all destinations (B-14) — depends on T-06. Verified: Help dialog in `lib/app/app.dart` describes all five tabs and Settings; no test pinned the old text.
- [x] T-18 Cache drawer notebook/note tree instead of `FutureBuilder` per open (P-02). Finding: the future was already cached in state and reloaded only on workspace change. The real defect was `_reloadNotebooks` using an arrow-body `setState` that returned a Future, which Flutter rejects. Fixed with a block body. Regression test `drawer reloads notebooks only when the workspace changes`; 4/4 drawer tests pass.
- [x] T-26 Reduce drawer and menu rebuilds in app shell (P-01). Verified: `_appMenu` and per-destination `_navigationDrawers` cached in `app.dart`; full suite passes.
- [x] T-27 Replace `debugPrint` in Notes with project logging approach (B-10) — depends on T-16. Verified: uses `developer.log(..., error:)`; analyze clean, notes tests pass.
- [x] T-28 User-entered timer labels (Timer gap) — depends on T-01. Verified: optional label field in the setup sheet (max 40 chars, trimmed), persisted as `label`, restored only when non-empty, shown on the card and in the finished alert. New test `labeled timer shows the label and restores it`; 9/9 timer tests pass.
- [x] T-29 Stopwatch fastest/slowest lap highlight (U-06) — depends on T-10. Verified: text plus icon (`Icons.bolt` fastest, `Icons.hourglass_bottom` slowest), shown only with 2+ laps and unequal splits; 2 new tests, 8/8 stopwatch tests pass.
- [x] T-30 Consolidate Search entry points — depends on T-14. Verified: drawer "Search notes" now navigates to Notes and focuses the inline search bar (`focusSearch()`), replacing the separate dialog. Full suite passes; no dedicated test for the drawer path.

## Final Quality Checklist (report section 10)

- [ ] `flutter analyze` clean
- [ ] `flutter test` passing, with new tests for timer restore, snooze default, stopwatch lap behavior
- [ ] Existing reminder, recurrence, and notification behavior verified unchanged

## Notes, Deviations, and Blockers

- **Deviation (T-04):** Notification-only reminders keep `soundUri: null`, so they never use the alarm tone. This is intentional and covered by an existing test. No code change was made. Custom tones apply to alarm-mode reminders. Needs device check.
- **Deviation (T-03):** The Settings snooze options (5, 10, 15, 30, 60 minutes) were chosen by me, not taken from the report.
- **Limitation (T-02, T-05):** There is no device or emulator here. Timer alert sound, vibration, and notification delivery are covered only by unit and widget tests. The T-05 save-failure SnackBar path has no test yet.
- **Limitation (T-02):** A timer that expires while the app is closed does not alert on restore. This is a deliberate choice, and it is open for review.
- **Done (T-19, T-20):** Theme roles and tab-state work are complete. Tests use `.hitTestable()` where offstage tabs share a finder with visible controls.
- **Partly done (T-21):** Compact IconButtons in the Calendar header and the note table embed now use the default 48 dp target. Chips with `shrinkWrap` are left as visual tags. Still open: non-color cues and a text-scale audit.
- **Pending (T-23, T-40):** T-23 splits the large Calendar and Rich Note Editor screens. T-40 is a full line-by-line review of Calendar, Notes editor, and Add Reminder. Each needs its own pass with per-screen verification.
- **Open questions for the user:** Should a timer that expires while the app is closed alert on restore? Are the snooze options (5, 10, 15, 30, 60 minutes) right? Is the T-12 finished-state design (Finished label, Restart, Stop and dismiss) right? Is the 40-character label limit (T-28) right?
- **APK (device testing):** `flutter build apk --release` produces `build\app\outputs\flutter-apk\app-release.apk` (about 62 MB). It is signed with the debug key, so it is for testing only and not for Play Store upload.
- **Deviation (T-05):** The save-failure SnackBar has no test. Triggering a SharedPreferences write failure needs a mock or fake platform store, and no such dev dependency exists. I did not add one.
- **Deviation (T-30):** The drawer "Search notes" entry now focuses the inline Notes search instead of opening a dialog. No dedicated test covers the drawer path.
- **Deviation (T-15):** The Notes editor's More menu still shows "Help and feedback are not available here yet." (`rich_note_editor_screen.dart`). It is outside the report's scope, so I left it.
- **Build status (latest):** `flutter analyze` reports no issues. `flutter test` passes all 216 tests. Release APK builds successfully.
- Nothing is committed. Pre-existing uncommitted changes were left in place.
