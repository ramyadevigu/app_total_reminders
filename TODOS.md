# TODOS

## Review

### Recover malformed reminder data across readers

**What:** Give foreground screens and background notification callbacks an explicit, recoverable error path when reminder storage contains malformed data.

**Why:** The current reader returns an empty list for corrupted JSON, which can hide reminders. The Connected Productivity MVP plan separately prevents mutations from overwriting the original payload; users still need a clear recovery path.

**Pros:** Readers can explain the problem and preserve the user's data instead of presenting a misleading empty reminder list.

**Cons:** This changes the shared storage error contract and requires consistent handling across more than five consumers and callback paths.

**Context:** `ReminderStorage` currently treats malformed reminder JSON as an empty result, and the existing storage test codifies that read behavior. The approved MVP plan adds mutation-safety checks but defers visible, app-wide recovery. Start by inventorying every foreground and background reader, then define one shared error result and recovery behavior that preserves the raw stored value. Add regression tests for each consumer and callback path.

**Effort:** Human: M / CC+gstack: S
**Priority:** P2
**Depends on:** The approved reminder-mutation safety change and an inventory of all `ReminderStorage` readers.

### Coordinate reminder scheduling across isolates

**What:** Prevent startup reminder reconciliation from scheduling a stale snapshot while reminder CRUD or a background callback changes the same reminder from another isolate.

**Why:** `ReminderStorage._runSerialized` coordinates operations only within its Dart Zone/isolate. The approved connected-workflow change serializes startup reconciliation with same-isolate mutations, but does not coordinate separate isolates.

**Scope:** Trace the platform callback and startup execution contexts, identify the stale-snapshot interleavings, and choose the smallest reliable cross-isolate coordination or revalidation strategy. Add deterministic regression tests for the selected strategy. Do not describe same-isolate serialization as solving this case.

**Effort:** Human: M / CC+gstack: S
**Priority:** P2
**Depends on:** The approved same-isolate startup reconciliation serialization and callback-path inventory.

### Set Budget Phase 2 data semantics before implementation

**What:** Before designing or implementing Budget Phase 2, inspect for an existing Budget Planner and explicitly settle month boundaries and timezone/DST behavior, supported currency and precision (including whether conversion is unsupported), planned-expense identity and duplicate handling, and financial-reminder ownership/linkage when an expense changes or is removed.

**Why:** These choices determine persisted meaning and reminder lifecycle. Guessing them during implementation can make monthly totals inconsistent, duplicate expenses, or leave financial reminders orphaned.

**Scope:** This is a pre-implementation decision gate for the already-approved later Budget slice. Record the decisions, migration impact, and tests; obtain product-owner approval before schema changes or code. Do not add accounting/bank integrations or a parallel reminder system.

**Effort:** Human: S / CC+gstack: S
**Priority:** P2
**Depends on:** Completion and review of the connected-workflow milestone and five-weekday observation gate.
