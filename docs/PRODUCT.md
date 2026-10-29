# Product

## 1. The user's words

### Original request (verbatim)

> I want you to create an iOS app that is a todo list app
>
> The application needs to be able to have the following building blocks:
> - Tasks
> - Note
> - Calendar
> - Reminder
> - Blob
>
> The UI will be based on simplicity and reduction of steps to interact, basically we don't want users to stay in the app at all, we want them to do stuff
>
> Once a task gets done it gets archived indefinitely
>
> Tasks can be linked as subtasks or as a sequence
>
> Another crucial part of the app is projects and lists, projects are meant to be completed whereas lists are meant to be infinite or never ending
>
> A task can have as many notes and reminders as needed, but there is only one main reminder that is used as the base
>
> A reminder can be a sticky notification or an alarm
>
> We need to have an easy way to reschedule tasks without changing the schedule of the task itself and the reminders need to be updated accordingly
>
> A task can have as many blobs as needed or it can be a blob itself
>
> The calendar is a multi view that shows all the tasks and their deadlines and start dates in a simple fashion with multiple time frames

### Clarifying questions and the user's answers

| # | Claude asked | User answered (verbatim) |
|---|---|---|
| 1 | Is a blob any captured content (photo, file, scan, voice memo, link), and can a blob *be* the task? Which types matter? | "Yes your interpretation is correct, all of those matter at the same degree" |
| 2 | Is rescheduling a temporary override kept separate from the plan? If the new date passes and the task isn't done, does it stay overdue or go back to the original plan? | "Yes that is right, and it should go to the original plan" |
| 3 | Recurring tasks? | "Yes it should have recurring tasks" |
| 4 | Sequences: when A is done, does B just unlock, or are B's dates calculated from when A finished? | "When A is done B unlocks but both can have their own schedule but obviously the deadline of one cannot go further than the start date of the next one" |
| 5 | Does finishing every subtask automatically finish the parent? How deep can nesting go? | "Yes, only one nesting as we want to keep them out of the app not leave there" |
| 6 | Are notes only attached to tasks, or can they stand alone? | "Notes can stand alone in both lists or projects" |
| 7 | Should the calendar also show Apple Calendar events? | "It should have a toggle to show only tasks or to include events from the Apple calendar" |
| 8 | iPhone only, or also iPad/Watch? iCloud sync? | "iPhone only and yes I want iCloud" |
| 9 | Can archived tasks be restored? | "Archived tasks can be cloned not restored, which also points that any task can be cloned" |

After seeing the architecture (`ARCHITECTURE.md`), the user moved on to setting up a Mac. They did **not** answer the four follow-up questions. Those are in `PLAN.md` §1.

## 2. Product principle

**People should not stay in the app. They should do stuff.** Every design choice is judged by this.

- Core actions take one or two taps: capture, complete, reschedule.
- Wherever iOS allows, people act from outside the app: notification buttons, alarm buttons, Lock Screen Live Activities, interactive widgets, Siri, Shortcuts, the Action button, Control Center, and the share sheet.
- Capture without typing: a photo, scan, voice memo, file or link can become a task on its own.
- Ask for permissions only when the feature is first used. For example, calendar access is requested when the Apple Calendar toggle is turned on.
- Keep structure shallow, with only one level of subtasks. The user explained this as "we want to keep them out of the app not leave there".

## 3. Rules

**Confirmed** means the user agreed to it. **Proposed** means Claude suggested it and the user has not confirmed it. Ask before building on a proposed rule.

### Tasks

- **T1 (Confirmed).** A task has a title and optionally a start date, a deadline and a recurrence rule. Together these are its **plan**.
- **T2 (Confirmed).** When a task is done, it is **archived indefinitely**. Archived tasks are read-only.
- **T3 (Confirmed).** Archived tasks **cannot be restored**. They can be **cloned**, and **any task**, active or archived, can be cloned. A clone is a new active task.
- **T4 (Confirmed).** Recurring tasks exist.
- **T5 (Proposed).** Completing a recurring task archives that occurrence and moves the task on to its next occurrence. The series keeps going.
- **T6 (Proposed).** Recurrence supports both a fixed schedule ("every Monday") and recurrence counted from completion ("2 weeks after I last did it").
- **T7 (Proposed).** If a recurring occurrence is missed, it stays overdue until it is done. Completing it moves on to the next *future* occurrence, so missed occurrences don't pile up.

### Subtasks and sequences

- **S1 (Confirmed).** Subtasks are **one level deep**. A subtask cannot have subtasks.
- **S2 (Confirmed).** When every subtask is done, the parent is done automatically and is archived.
- **S3 (Proposed).** If the user completes a parent directly while some subtasks are still open, those subtasks are archived along with it. This takes one tap with no blocking dialog.
- **S4 (Confirmed).** In a sequence A → B, **B is locked until A is done**. When A is done, B unlocks.
- **S5 (Confirmed).** Each task in a sequence has its own schedule, but **A's deadline cannot be later than B's start date**.
- **S6 (Proposed).** S5 applies only when both dates are set. An edit that would break it is blocked, and the user is offered a one-tap "shift the next task" fix.
- **S7 (Proposed).** Recurring tasks cannot be part of a sequence, because "B unlocks when A is done" is unclear if A repeats forever.
- **S8 (Proposed).** The subtasks of one parent can form a sequence (step 1 → step 2 → step 3).
- **S9 (Proposed).** Locked tasks appear greyed out in their project or list and are hidden from the "Now" screen.

### Projects and lists

- **C1 (Confirmed).** **Projects** are meant to be completed. **Lists** never end.
- **C2 (Proposed).** Completing a project archives it, the same way a task is archived.
- **C3 (Proposed).** When a project with unfinished tasks is completed, the user is asked once whether to move the leftovers to the Inbox or archive them with the project.
- **C4 (Proposed).** There is an **Inbox** for anything captured without a project or list. Each task belongs to exactly one container: the Inbox, a list or a project.

### Notes

- **N1 (Confirmed).** A task can have any number of notes.
- **N2 (Confirmed).** Notes can also **stand alone in a list or a project**.

### Reminders

- **R1 (Confirmed).** A task can have any number of reminders, but **exactly one main reminder**, which is the base.
- **R2 (Confirmed).** Each reminder is either a **sticky notification** or an **alarm**.
- **R3 (Confirmed, as Claude interpreted it and the user accepted).** The other reminders are set relative to the main reminder, for example "1 day before main". When the main reminder moves, they all move with it.
- **R4 (Proposed).** The main reminder is set relative to the task's **do date**: the start date, or the deadline if there is no start date. Examples are "on the day at 9:00" and "30 minutes before".
- **R5 (Proposed, open).** Should some reminders stay tied to the deadline and *not* move when the task is rescheduled, like a "deadline is tomorrow" warning? Not decided.
- **R6 (Proposed).** A sticky reminder is a Lock Screen Live Activity scheduled for the reminder time, plus a time-sensitive notification that repeats until acted on. A suggested default is every 10 minutes, up to 6 times. See ARCHITECTURE §4.3 for why both are used.
- **R7 (Proposed).** An alarm rings through Silent mode and Focus using AlarmKit. Its secondary button is **Done**, which completes the task straight from the ringing alarm.
- **R8 (Proposed).** If a reminder is added to an undated task, the reminder's time becomes the task's start date.

### Rescheduling

- **D1 (Confirmed).** Rescheduling **never changes the task's plan**. It sets a temporary **override** of the do date.
- **D2 (Confirmed).** All reminders follow the override automatically. No reminder needs to be edited by hand.
- **D3 (Confirmed).** If the override date passes and the task is not done, the task **goes back to its original plan**.
- **D4 (Proposed).** The deadline is never moved by rescheduling. If the override is after the deadline, the task is marked "late" but the move is allowed.
- **D5 (Proposed).** An override expires at the end of its day in local time. Completing the task clears it. For a recurring task, the override applies only to the current occurrence.
- **D6 (Proposed).** One-tap presets: **Tonight** (19:00), **Tomorrow** (same time of day, or 09:00), **Next week** (+7 days), and **Pick…**. These are offered on notifications, Live Activities, widgets and in the app.

### Blobs

- **B1 (Confirmed).** A blob is any captured content: a **photo, scan, file, voice memo or link**. All five types matter equally.
- **B2 (Confirmed).** A task can have any number of blobs, **or be a blob itself**. For example, photograph a letter and that photo is the task. No typing is required, and a title is suggested from the content.

### Calendar

- **K1 (Confirmed).** The calendar shows tasks with their start dates and deadlines, simply, in several time frames.
- **K2 (Confirmed).** A toggle switches between showing only tasks and also showing Apple Calendar events.
- **K3 (Proposed).** The views are Day, Week, Month and Agenda (a list). A task with both a start and a deadline is drawn as a span. Rescheduled tasks show at their override date, with the original plan indicated.
- **K4 (Proposed).** Apple Calendar events are read-only in this app.

### Platform

- **P1 (Confirmed).** iPhone only.
- **P2 (Confirmed).** iCloud sync.
- **P3 (Agreed in the architecture).** iOS 26 minimum (AlarmKit), no server of our own, and no third-party dependencies.
