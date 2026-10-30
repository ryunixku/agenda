# Agenda: iPhone to-do app

A first full version of the app exists: every milestone (M1–M7) is built and checked in the iOS Simulator. What's left is testing on the user's iPhone (see `docs/PLAN.md` §5), which needs a real Apple Developer Team ID and bundle ID.

## Read these, in order

1. [`docs/PRODUCT.md`](docs/PRODUCT.md): what the user wants, in their own words. Rules marked **Confirmed** were agreed by the user. Rules marked **Proposed** were not.
2. [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): the architecture the user saw, and why it fits the product.
3. [`docs/PLAN.md`](docs/PLAN.md): what to ask the user first, what they need to provide, and the milestones.

## The short version

A to-do app built so people spend as little time in it as possible. They capture, act and leave. Most actions happen outside the app: notification buttons, alarms, Lock Screen Live Activities, widgets, Siri, Shortcuts, and the share sheet. The building blocks are Tasks, Notes, Reminders, Blobs and the Calendar, organised into Projects (they finish) and Lists (they never finish). Done tasks are archived forever and can be cloned, never restored.

## Fixed constraints (confirmed by the user)

- iPhone only, with iCloud sync. iOS 26 is the minimum, because alarms need AlarmKit.
- One level of subtasks. Sequences unlock the next task when the previous one is done.
- Rescheduling never changes a task's own schedule. When the rescheduled day ends without completion, a one-off task shows as overdue since that day, and a recurring task goes back to its schedule.
- Done tasks are archived with an outcome (done or not done). Any task can be deleted for good.
- One main reminder per task. All other reminders hang off it. A reminder is either sticky or an alarm.

## How to work in this repo

- **All rules live in the core package (`AgendaCore`, in `AgendaKit/`).** The app, widgets, intents, notification handlers and extensions call the same actions. Never re-implement a rule in a view or an extension.
- **All writes go through `AgendaStore.perform` (`AgendaData`).** It runs a core rule and saves only what changed. `SharedStore.shared` is the one store; each target's `SharedStore.afterChange` decides what follows a change (reminders, widget reloads).
- **Test with `swift test` in `AgendaKit/`.** Core and storage tests name the rule IDs they cover. Add a test with every rule change.
- **Proposed rules are not confirmed.** Before building on one, ask the user. `docs/PLAN.md` §1 lists what to ask first.
- **No third-party dependencies.**
- **Generate the Xcode project with XcodeGen** from `project.yml`. Don't hand-edit `.pbxproj`. Info.plist and `.entitlements` files are generated from `project.yml` too, and are not committed. Re-run `xcodegen` after adding or removing files.
- **Placeholders:** `APP_BUNDLE_ID` (`com.example.agenda`) and `DEVELOPMENT_TEAM` (empty) at the top of `project.yml`. The App Group and iCloud container are derived from `APP_BUNDLE_ID`. Until the user provides real ones, builds are Simulator-only and iCloud doesn't sync.
- **Verify before reporting done:** run `swift test` for the package, build for the iOS Simulator, launch the app, and look at a screenshot. Some things only work on a real device: alarms, notifications, iCloud sync and Live Activities. Tell the user what still needs testing on their iPhone; don't claim it works.
- **Ignore the other branches** (`codex/todo-app`, `claude/todo`). They are unrelated earlier attempts and not part of this plan.
- **Use the user's language.** Keep explanations plain and short. The user cares about how a feature serves "do stuff, don't stay in the app".

## Build and run

```sh
xcodegen                                    # in the repo root
swift test --package-path AgendaKit         # core tests, no simulator needed
xcodebuild -project Agenda.xcodeproj -scheme Agenda \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath DerivedData build
# The app is then at DerivedData/Build/Products/Debug-iphonesimulator/Agenda.app
# `xcodebuild … test` runs the package tests on the simulator too.
```

- **Sample data:** a debug build launched with `-demo` on an empty store fills in lists, a project, a sequence, subtasks and reminders (`App/DemoData.swift`): `xcrun simctl launch booted com.example.agenda -demo`.
- **Reminder engine log:** `xcrun simctl spawn booted log show --last 5m --info --predicate 'subsystem == "Agenda"'` shows what each run scheduled.
- **The Simulator can't** ring AlarmKit alarms (permission is always denied there, so alarms fall back to notifications), start Live Activities on a schedule, or sync with iCloud without a team. Those are on the device checklist.
- **Other sessions on this Mac may use the same Simulators** (a Todo app from another project was being installed onto the iPhone 17 while this was built). Use a Simulator of your own if apps start switching by themselves.

## Status

- [x] Product idea agreed
- [x] Architecture agreed
- [x] Open questions in `docs/PLAN.md` §1 answered
- [x] M1 Core rules and tests
- [x] M2 Xcode project skeleton (with placeholder IDs; see above)
- [x] M3 Storage and iCloud (sync untested: needs a real team and iCloud container)
- [x] M4 In-app screens
- [x] M5 Reminder engine (notifications checked in the Simulator; alarms and Live Activities need a device)
- [x] M6 Out-of-app surfaces (widget, share extension and App Intents checked in the Simulator)
- [x] M7 Calendar
- [ ] Device checklist in `docs/PLAN.md` §5
- [ ] M8 (optional) CI

Update this checklist as milestones land.
