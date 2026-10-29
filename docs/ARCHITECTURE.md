# Architecture

This is the architecture the user saw and agreed to, with the reasons for each decision. Rule IDs such as `D3` or `S5` refer to `PRODUCT.md`.

## 1. Overview

A native SwiftUI app with no server of its own. One core holds every rule. Every place a person can act goes through that core using the same set of actions. The core stores only the plan and works out dates and reminder times when they are needed.

```
WHERE PEOPLE ACT
  App · Widgets · Lock Screen Live Activities · Notification buttons
  Alarms (AlarmKit) · Siri / Shortcuts / Action button / Control Center · Share sheet
                         │
        One set of actions: Add · Capture · Done · Reschedule · Clone · What's next
                         │
CORE (AgendaCore: plain Swift, no UI, no database)
  Scheduling · Recurrence · Overrides · Reminder times
  Sequences · Subtasks · Archive · Clone · Validation
                         │
     ┌───────────────────┼──────────────────────┐
  STORAGE             REMINDER ENGINE         CALENDAR FEED
  SwiftData +         Reconciles what should  Task occurrences
  iCloud (CloudKit)   fire → notifications,   + Apple Calendar
  in an App Group     AlarmKit, Live Activities (EventKit, toggle)
```

## 2. Module layout

```
project.yml                  XcodeGen spec (generates Agenda.xcodeproj; don't commit the generated project)
AgendaKit/                   local Swift package
  Sources/AgendaCore/        rules and scheduling. Foundation only, so tests run without a simulator
  Sources/AgendaData/        SwiftData models, CloudKit configuration, the Actions layer (all writes)
  Sources/AgendaDelivery/    reminder engine: UserNotifications, AlarmKit, ActivityKit
  Sources/AgendaIntents/     App Intents, App Entities, App Shortcuts
  Sources/AgendaUI/          SwiftUI screens
  Tests/AgendaCoreTests/     most of the tests live here
  Tests/AgendaDataTests/     Actions tested against an in-memory store
App/                         app target (thin: entry point, notification delegate, background tasks)
Widgets/                     widget extension: widgets, Live Activities, Control Center controls, alarm presentation
Share/                       share extension: capture blobs from other apps
```

App Intents can live in a Swift package using `AppIntentsPackage`. If metadata extraction causes trouble, compile the intents source folder directly into the app and widget targets instead.

The names (`Agenda`, `AgendaKit`, …) are working names taken from the repo. Change them if the user wants a different app name.

## 3. Decisions and why

### 3.1 All rules live in one core (`AgendaCore`)

**What.** Plain Swift types and functions:
- one level of subtasks (S1)
- parent auto-completes (S2)
- sequence locking (S4) and the date constraint (S5)
- exactly one main reminder (R1)
- archived tasks are read-only (T2)
- clone (T3)
- recurrence, overrides, and resolving reminder times

**Why.** People change tasks from six or more places: the app, a widget, a notification, an alarm, a Live Activity, Siri, and the share sheet. If the rules lived in screens or extensions, each place would re-implement them and they would drift apart. Tapping "Done" on the Lock Screen must run exactly the same code as tapping it in the app.

The hardest logic is recurrence, overrides, reminder offsets, time zones and daylight saving. That is where to-do apps usually get bugs. As pure functions it can be unit-tested thoroughly with an injected clock and calendar.

### 3.2 Store the plan, calculate everything else

**Stored per task:**
- **Plan:** start, deadline, recurrence. Changed only by editing the task.
- **Override:** a single "moved to" date. Changed only by Reschedule (D1).
- **Reminders:** the main one is relative to the do date (R4). The others are offsets from the main one (R3).

**Calculated on demand (never stored):**
- **Effective do date:** the override, if it hasn't expired (D5). Otherwise the plan's current occurrence.
- **Reminder fire times:** effective do date → main reminder → other reminders.
- **Task state:** open, locked (predecessor not done), overdue, late (override after deadline).

**Why this supports the product:**
- Reschedule is one write, and every reminder follows (D2).
- When the override passes, the task falls back to the plan (D3). No cleanup job is needed, because the calculation sees the override has expired. The expired override can be removed lazily.
- For recurring tasks, completing archives the occurrence, clears the override and moves the plan to the next occurrence. Reminders follow.
- The calendar uses the same calculation, so it can never disagree with the notifications.

Day offsets such as "1 day before" should be added as calendar days, so the time of day survives daylight-saving changes. Store dates rounded to the minute so comparisons stay stable after an iCloud round trip.

### 3.3 The reminder engine reconciles instead of scheduling one-off calls

**What.** After any change, the engine:
1. computes the full list of deliveries that should exist,
2. diffs that list against what iOS currently has scheduled,
3. adds and removes the difference.

A change means any of these: an edit, a completion, a reschedule, data arriving from iCloud, app launch or foreground, a time zone or significant time change, a background app refresh, or a notification being delivered or acted on.

Every delivery has a **stable ID** (task + reminder + occurrence), so running the engine twice changes nothing.

**Why:**
- Reminders can't be left at an old time or orphaned. They always reflect the data, including after iCloud sync.
- iOS allows only **64 pending local notifications per app**. Multiple reminders per task, recurrence and sticky repeats would exceed that quickly. The engine schedules the nearest deliveries, keeps some headroom, and tops up whenever it runs.
- Routing by kind happens in one place (see §4.3).

### 3.4 One set of actions behind every surface (App Intents)

**What.** Each user-facing action is defined once as an App Intent, calling the Actions layer: Add task, Capture blob, Done, Reschedule (presets and Pick), Clone, and What's next. Tasks are exposed as an `AppEntity` so Siri, Shortcuts and Spotlight can refer to them.

**Why.** This is what makes "don't stay in the app" possible. Apple uses App Intents for:
- interactive widget buttons
- Live Activity buttons
- AlarmKit alarm buttons
- Siri, Shortcuts and Spotlight
- the Action button and Control Center controls

Each action is written once and works in all of those places, always under the core rules. Notification action buttons are `UNNotificationAction`s, not intents; their handler calls the same Actions.

### 3.5 SwiftData + iCloud (CloudKit private database), no server

**What.** On-device SwiftData store, synced through the user's private CloudKit database. The store lives in an **App Group** container so the app, widget extension and share extension all read the same data. Blob bytes use `@Attribute(.externalStorage)` and sync as CloudKit assets.

**Why:**
- It matches "iPhone only + iCloud" exactly. There is no backend to build, host or pay for, the data stays in the user's iCloud, and the app works offline.
- **Trade-off:** CloudKit-backed SwiftData does not support unique constraints, required relationships, or the `.deny` delete rule. Every attribute must be optional or have a default. So invariants such as "exactly one main reminder" must be enforced in the core, not by the database. That is another reason for §3.1.
- **Escape hatch:** storage is separate from the core, so the app could switch to Core Data (`NSPersistentCloudKitContainer`) later without touching the rules.
- Blobs count against the user's iCloud storage.

### 3.6 UI: thin SwiftUI screens

SwiftUI with the Observation framework (`@Observable`). No third-party architecture framework. The complex logic is in the core, so the screens stay simple.

| Screen | Purpose |
|---|---|
| **Now** (home) | What's actionable today: open, not locked, do date ≤ today, plus overdue |
| **Capture** | One text field that is always ready, plus Camera, Scan, Voice, File and Link buttons |
| **Lists & Projects** | Containers, their tasks and their standalone notes |
| **Calendar** | Day / Week / Month / Agenda, plus the Apple Calendar toggle |
| **Archive** | Search, view (read-only), Clone |

Task details open as a **sheet** rather than a pushed screen, so the user is never deep in navigation.

## 4. Key mechanisms

### 4.1 Data model (sketch)

```
Container        kind: inbox | list | project; name; order; completedAt? (projects)
  ├─ tasks[]
  └─ notes[]     standalone notes (N2)

Task
  title, container, order
  parent?                      one level only (S1)
  previous? / next?            sequence; derived "locked" state (S4)
  plan: start?, deadline?, recurrence?
  override?: Date              reschedule (D1); current occurrence only
  reminders[]                  exactly one isMain when non-empty (R1)
  notes[]
  blobs[]
  primaryBlob?                 the task IS this blob (B2)
  clonedFrom?: task id
  archivedAt?                  set = archived, read-only (T2)

Reminder         kind: sticky | alarm; isMain; offset
                 (main: relative to the do date; others: relative to main)
Note             text, createdAt; owner = a task or a container
Blob             kind: photo | scan | file | voice | link; data (external storage);
                 thumbnail; url; filename; typeIdentifier; extractedText (OCR/transcript/page title)
Completion       one per completed occurrence of a recurring task:
                 taskID, occurrence date, completedAt, title snapshot (the archive entry)
```

- **One-off task done:** the task itself gets `archivedAt` and becomes read-only. Nothing is copied.
- **Recurring task done:** a lightweight `Completion` entry is archived. The task moves on (T5). Blobs are not duplicated per occurrence.
- **Clone:** one core operation for any task, active or archived. It creates a new active task and copies fields, notes, reminders and blobs. Blob data is copied so the clone is independent.

### 4.2 Calendar feed

The feed expands each task's occurrences inside the visible range, using the effective dates from §3.2. When the toggle is on, it merges read-only Apple Calendar events from EventKit. Calendar access (`requestFullAccessToEvents`) is requested only when the user first turns the toggle on.

### 4.3 Reminder routing

- **Alarm → AlarmKit.** A real alarm that sounds through Silent mode and Focus. `AlarmConfiguration` takes an optional `stopIntent` and `secondaryIntent` (both `LiveActivityIntent`). These run in the app's process even when the app isn't running, so a **Done** button on the alarm can complete the task (R7).
- **Sticky →** a **Live Activity scheduled to start at the reminder time**, plus a **time-sensitive notification** that repeats until the user acts (R6).
  - iOS 26 can schedule a Live Activity on the device (`Activity.request(…, start: Date)`), so no push server is needed.
  - The Live Activity shows the task on the Lock Screen with Done and Reschedule buttons (App Intents).
  - iOS ends Live Activities after several hours, so the repeating notification is the backstop.
  - If several sticky reminders are due at once, group them into one "Now" activity rather than one activity each.
- **Notification actions** (category per kind): Done, Tomorrow, In 1 hour / Tonight, and Pick… (opens a small sheet). All of them call the Actions layer and then re-run the engine.

### 4.4 Out-of-app surfaces

- Actionable notifications, as above.
- AlarmKit alarms with a Done button.
- A Lock Screen / Dynamic Island Live Activity for sticky reminders.
- Interactive Home and Lock Screen widgets: the next few tasks, each with a check button.
- A Control Center control and the Action button for instant capture.
- Siri, Shortcuts and Spotlight through App Intents and App Shortcuts ("Add a task", "What's next").
- A share extension: capture a photo, link, file or text from any app as a new task, or attach it to an existing one.

## 5. Platform facts and how sure we are

Verify anything not marked *verified* against the Xcode SDK and Apple's current documentation before relying on it.

| Fact | Status |
|---|---|
| AlarmKit is iOS 26+. Alarms sound through Silent mode and Focus. Requires user authorization and an `NSAlarmKitUsageDescription` usage string. | From memory; verify |
| `AlarmManager.AlarmConfiguration` has optional `stopIntent` / `secondaryIntent` (`LiveActivityIntent`), run in the app's process even if the app isn't running | Verified ([Apple](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmconfiguration/init(countdownduration:schedule:attributes:stopintent:secondaryintent:sound:)), [guide](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit)) |
| A widget extension is required for AlarmKit countdown presentation, or alarms may be dismissed unexpectedly | Third-party claim only; unverified. We have a widget extension anyway. |
| iOS 26 can schedule a Live Activity to start at a future date on device: `Activity.request(attributes:content:pushType:style:alertConfiguration:start:)` | Verified ([Apple](https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:style:alertconfiguration:start:))) |
| A scheduled Live Activity start may create a second activity instead of updating an existing one | Developer-forum report; unverified. Design around it. |
| Live Activities last about 8 h active, then up to about 4 h more on the Lock Screen | From memory; verify |
| Live Activity attributes plus content state must fit within 4 KB | From search; verify |
| Max 64 pending local notifications per app | Well known |
| Time-sensitive notifications need the Time Sensitive Notifications capability and `interruptionLevel = .timeSensitive` | From memory; verify |
| SwiftData + CloudKit: no `.unique`, attributes optional or defaulted, relationships optional, no `.deny` delete rule | Well known |
| iCloud / CloudKit capability needs a paid Apple Developer Program team | From memory; verify |
| EventKit reading needs `requestFullAccessToEvents` (iOS 17+) and `NSCalendarsFullAccessUsageDescription` | From memory; verify |
| Interactive widgets use `Button(intent:)` (iOS 17+). Control Center controls exist on iOS 18+ | From memory; verify |
| Blob capture: PhotosPicker / camera, VisionKit document scanner, AVAudioRecorder, `fileImporter`, LinkPresentation for link previews | Standard APIs |

## 6. Tooling

- **XcodeGen** (`brew install xcodegen`, then `xcodegen` in the repo root). The project is defined in a readable, diffable `project.yml` instead of a `.pbxproj` that is hard for an agent to edit safely. Add the generated `Agenda.xcodeproj` to `.gitignore`.
- **Tests:** `swift test` inside `AgendaKit/` for the core. `xcodebuild test` against an iOS Simulator for everything else.
- **Simulator checks:** `xcrun simctl list devices available` to pick a device, then `xcodebuild -scheme Agenda -destination 'platform=iOS Simulator,name=<device>' build`, then `xcrun simctl install/launch`, then `xcrun simctl io booted screenshot`.
- **CI (optional, later):** a GitHub Actions macOS workflow that builds and runs the tests on every push. On a private repo, macOS minutes are billed at a higher rate.
