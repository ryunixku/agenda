# Plan

## 1. Ask the user first

**Status (2026-10-29):** asked and answered on the Mac. The answers are in `PRODUCT.md` §1 (F1–F10, G1–G3). Nothing blocks M1.

Ask these in **one batch** before starting M1, with the suggested default for each, so the user can just say "defaults are fine". The rule IDs refer to `PRODUCT.md`.

**These affect the core rules, so settle them before M1:**

1. **Recurrence types (T6):** fixed schedule, counted from completion, or both? *Suggested: both.* (Asked before, not answered.)
2. **Recurring tasks in sequences (S7):** allowed? *Suggested: no.* (Asked before, not answered.)
3. **Subtasks as a sequence (S8):** can one parent's subtasks be ordered steps? *Suggested: yes.* (Asked before, not answered.)
4. **Completing a project with unfinished tasks (C3):** *Suggested: ask once, either move the leftovers to the Inbox or archive them with the project.* (Asked before, not answered.)
5. **Inbox (C4):** is there an Inbox, and does each task belong to exactly one container? *Suggested: yes and yes.*
6. **What rescheduling moves (R4, R5, D4):** the do date moves and the deadline never does. Should some reminders stay tied to the deadline and not move? *Suggested: not for now. All reminders follow the do date.*
7. **When an override expires (D5):** *Suggested: at the end of its day.*
8. **Missed recurring occurrences (T7):** *Suggested: the missed one stays overdue until done, and completing it jumps to the next future occurrence.*
9. **Completing a parent directly while subtasks are open (S3):** *Suggested: the open subtasks are archived with it.*
10. **Edits that break the sequence date rule (S6):** *Suggested: block the edit and offer a one-tap "shift the next task".*

**These can use the defaults now and be confirmed when the relevant milestone starts:**

- Reschedule presets and times (D6)
- How often sticky notifications repeat (R6)
- The alarm's secondary button being Done (R7)
- Which calendar views to offer (K3)
- How locked tasks are shown (S9)
- Adding a reminder to an undated task (R8)

After the user answers, update `PRODUCT.md`: change **Proposed** to **Confirmed**, or rewrite the rule.

## 2. What the user needs to provide

| Item | Needed for | Until then |
|---|---|---|
| App name and bundle ID prefix (e.g. `com.example.agenda`) | Project setup | Use `Agenda` and a placeholder ID |
| Apple Developer Team ID (paid program) | Signing, iCloud, App Groups, time-sensitive notifications, running on device | Simulator builds without iCloud |
| iCloud container ID (e.g. `iCloud.<bundle id>`) | M3 sync | Local-only store |
| App Group ID (e.g. `group.<bundle id>`) | Sharing the store with the widget and share extensions | Placeholder |
| Their iPhone (iOS 26+) | Testing alarms, notifications, Live Activities and iCloud | Simulator only |

## 3. Mac setup check

Check these before M2:
- Xcode 26 or later, with an iOS 26+ Simulator runtime (`xcodebuild -version`, `xcrun simctl list runtimes`)
- XcodeGen (`brew install xcodegen`)
- For iCloud testing in the Simulator: an Apple ID signed in on the Simulator

## 4. Milestones

Each milestone ends with a passing build and tests, a commit and a push. If the milestone has UI, also launch the app in the Simulator and take a screenshot to check it.

### M1: Core rules (`AgendaCore`) and tests
- Value types: plan, recurrence rule, override, reminder spec, sequence links, task state.
- Recurrence: generate occurrences, find the current occurrence, handle missed occurrences (T7).
- Effective do date, including override expiry and fallback to the plan (D1, D3, D5).
- Reminder fire times: main from the do date, others from main. Use calendar-day offsets so daylight-saving changes don't shift them.
- Validation: one subtask level, one main reminder, the sequence date rule, archived tasks read-only, no cycles in sequences.
- Complete (including parent auto-complete and recurring roll-forward), clone, archive.
- **Done when:** `swift test` passes, with tests for every Confirmed rule. Cover time zones and daylight saving.

### M2: Xcode project skeleton
- `project.yml` with targets App, Widgets and Share, linking the `AgendaKit` package. iOS 26 deployment target, iPhone only.
- Capabilities and Info.plist entries: App Group, iCloud (CloudKit), Push Notifications (for CloudKit sync), Background Modes (remote notifications, background fetch), Time Sensitive Notifications, `NSSupportsLiveActivities`, AlarmKit usage string, calendar usage string, camera and microphone usage strings.
- **Done when:** `xcodegen && xcodebuild … build` succeeds and an empty app launches in the Simulator.

### M3: Storage and iCloud (`AgendaData`)
- SwiftData models that follow the CloudKit constraints, stored in the App Group container.
- The Actions layer, which is the only way to write data. Every action runs the core validation and then notifies the reminder engine and reloads widgets.
- **Done when:** the Actions tests pass against an in-memory store. A device sync test is listed for the user.

### M4: In-app screens (`AgendaUI`)
- Now, Capture (text plus all five blob types), Lists & Projects (including standalone notes), the task detail sheet, Archive (search, view, Clone).
- The one-tap reschedule presets, available everywhere.
- **Done when:** every screen has been checked by screenshot in the Simulator, and each core action takes two taps or fewer.

### M5: Reminder engine (`AgendaDelivery`)
- The reconciler (§3.3 of ARCHITECTURE), with stable IDs and the rolling window under the 64-notification limit.
- Sticky: a scheduled Live Activity plus repeating time-sensitive notifications. Alarm: AlarmKit with a Done button.
- Notification categories and actions.
- **Done when:** the reconciler is unit-tested (desired set vs. scheduled set). The device checklist covers sticky, alarm, reschedule-from-notification and override expiry.

### M6: Out-of-app surfaces (`AgendaIntents`, Widgets, Share)
- App Intents and App Shortcuts, the Task `AppEntity`, interactive widgets, a Control Center capture control, Live Activity buttons, and the share extension.
- **Done when:** each surface works in the Simulator where possible, and the rest is on the device checklist.

### M7: Calendar
- Day, Week, Month and Agenda views, with start→deadline spans and override indicators.
- The Apple Calendar toggle, with permission requested on first use and events shown read-only.
- **Done when:** checked by screenshot in each view with the toggle off and on.

### M8 (optional): CI
- A GitHub Actions macOS workflow: generate the project, build, and test.

## 5. Device checklist (for the user's iPhone)

Keep this list updated as milestones land. Report it honestly; don't mark an item as passing unless it was tested on a device.

Before any of this: set the real `APP_BUNDLE_ID` and `DEVELOPMENT_TEAM` in `project.yml`, run `xcodegen`, and run on the iPhone from Xcode.

Checked in the Simulator only (still worth a look on the device): widget check buttons, sharing a Safari page, notification scheduling with sticky repeats, the Apple Calendar toggle, App Intents registration.

- [ ] Alarm permission is asked when a reminder is first set to Alarm. The alarm rings in Silent mode and Focus. Done on the alarm completes the task.
- [ ] Sticky reminder appears as a Live Activity at its time, with Done / Tonight / Tomorrow working from the Lock Screen, and repeats as a notification every 10 minutes until acted on.
- [ ] Notification buttons: Done, Tonight and Tomorrow work without opening the app; Pick… opens the reschedule sheet.
- [ ] Reschedule from a notification moves all of that task's reminders.
- [ ] A recurring task's reschedule that passes falls back to its schedule; a one-off stays overdue since the new day.
- [ ] Data syncs between installs through iCloud (for example, delete and reinstall, or a second device).
- [ ] Widget check buttons and Siri / Shortcuts actions ("Add a task in Agenda", "What's next in Agenda") work without opening the app.
- [ ] The Control Center "Add to Agenda" button opens the app ready to type.
- [ ] Sharing from Photos, Safari and Files creates a task.
- [ ] Camera and document scanner capture (not available in the Simulator).
