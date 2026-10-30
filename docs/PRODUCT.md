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

### Follow-up questions and the user's answers (2026-10-29, on the Mac)

| # | Claude asked (suggested default) | User answered (verbatim) |
|---|---|---|
| F1 | Repeats on a fixed schedule, "X after I last did it", or either? (either) | "On a fixed schedule" |
| F2 | Can a repeating task be a step in a sequence? (no) | "No" |
| F3 | Can a task's subtasks be ordered steps that unlock one at a time? (yes) | "Yes" |
| F4 | Finishing a project with tasks still open? (ask once: move the leftovers to the Inbox, or archive them with the project) | "Archiving is the way to go, we want to keep the history of what was done and what doesn’t of course unless the user deletes the task" |
| F5 | Is there an Inbox, and does every task live in exactly one place? (yes, yes) | "Okay I guess is easier to have an inbox it should be a list as is meant to be temporary if the task is no assigned to another list or project after creation" |
| F6 | Rescheduling moves the do date, never the deadline. Should some reminders stay tied to the deadline? (no, all follow the do date) | "It should move the do date only of both if the new date passes even the deadline, life happens" |
| F7 | When does a reschedule run out: at the end of the new day, or as soon as its time passes? (end of the day) | "Please explain I don’t get it". After an example (planned Monday, moved to Tuesday, not done): "It should be A, although sounds a bit confusing, I mean, you didn't mentioned as a recurring task, because if is a recurring task, then you're right, but if not, then you're wrong, it should be saying overdue since Tuesday, no?" |
| F8 | A missed repeat stays overdue until done, then jumps to the next future date? | "agree" |
| F9 | Ticking off a parent while subtasks are open: the open ones are archived with it, no dialog? | "Yes default is archiving tasks as open but it needs to show the option to mark all subtasks as done" |
| F10 | An edit that breaks the sequence date rule is blocked, with a one-tap "shift the next task"? | "I agree" |

### Second follow-up (2026-10-29)

| # | Claude asked | User answered (verbatim) |
|---|---|---|
| G1 | Reading of F6: a new date past the deadline moves the deadline to that same day, temporarily. All reminders follow the do date. In a sequence, A may slip past B's start; B stays locked. | "I mean why guessing?, let the user update both quickly, no?" (The other two points were not objected to.) |
| G2 | Can archived tasks be deleted too, or only open ones? (both, with one confirmation) | "Yeah you should be able to delete any task you want regardless" |
| G3 | The Inbox is a built-in list that can't be deleted; new tasks land there unless put elsewhere. | "Correct" |

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
- **T6 (Confirmed, F1).** Recurrence is on a **fixed schedule** only, for example every Monday or the 1st of each month. There is no "X after I last did it".
- **T7 (Confirmed, F8).** If a recurring occurrence is missed, it stays overdue until it is done. Completing it moves on to the next *future* occurrence, so missed occurrences don't pile up.
- **T8 (Confirmed, F4, F9).** The archive keeps the history of what was done **and what wasn't**. Each archived task records its outcome: **done**, or **not done** (closed while still open, for example along with its project or parent).
- **T9 (Confirmed, F4).** The user can **delete** a task. A deleted task is gone for good, including from the archive. Apart from that, nothing is ever removed.
- **T10 (Confirmed, G2).** Any task can be deleted, active or archived.
- **T11 (Proposed).** Delete asks once to confirm, because it can't be undone. Deleting a parent deletes its subtasks. Deleting a task in the middle of a sequence joins its neighbours (A → B → C becomes A → C).
- **T12 (Proposed).** A clone copies the title, plan, reminders, notes, blobs and subtasks (as open, with their step order). It does not copy a reschedule or links to other tasks. A clone of a subtask stays under its parent while the parent is open. A clone of a task whose project is archived goes to the Inbox.
- **T13 (Proposed).** Dates are "floating": "Tuesday 10:00" means 10:00 local time wherever the user is. A date is either a whole day or a day with a time.

### Subtasks and sequences

- **S1 (Confirmed).** Subtasks are **one level deep**. A subtask cannot have subtasks.
- **S2 (Confirmed).** When every subtask is done, the parent is done automatically and is archived.
- **S3 (Confirmed, F9).** If the user completes a parent directly while some subtasks are still open, those subtasks are archived with it as **not done** by default (T8), and the app offers an option to **mark all subtasks done** instead.
- **S4 (Confirmed).** In a sequence A → B, **B is locked until A is done**. When A is done, B unlocks.
- **S5 (Confirmed).** Each task in a sequence has its own schedule, but **A's deadline cannot be later than B's start date**.
- **S6 (Confirmed, F10).** S5 applies only when both dates are set. An edit that would break it is blocked, and the user is offered a one-tap "shift the next task" fix.
- **S7 (Confirmed, F2).** Recurring tasks cannot be part of a sequence, because "B unlocks when A is done" is unclear if A repeats forever.
- **S8 (Confirmed, F3).** The subtasks of one parent can form a sequence (step 1 → step 2 → step 3).
- **S9 (Proposed).** Locked tasks appear greyed out in their project or list, are hidden from the "Now" screen, and their reminders don't fire until they unlock. A locked parent locks its subtasks.
- **S10 (Proposed).** In the app, the S3 option is a short banner right after the tap ("2 open subtasks archived as not done · Mark all done"), not a dialog in the way. From outside the app (widget, notification, Siri) the default applies.
- **S11 (Confirmed, G1, not objected to).** S5 constrains plans only. Rescheduling A past B's start is allowed ("life happens"). B stays locked until A is done.
- **S12 (Proposed).** A locked task can't be completed. A predecessor that is closed in any way (done, archived as not done, or deleted) unlocks the next task.
- **S13 (Proposed).** A sequence links top-level tasks to each other, or subtasks of the same parent. A task has at most one previous and one next task.
- **S14 (Proposed).** Recurring tasks can't have subtasks or be subtasks, for the same reason as S7.

### Projects and lists

- **C1 (Confirmed).** **Projects** are meant to be completed. **Lists** never end.
- **C2 (Confirmed, F4).** Completing a project archives it, the same way a task is archived.
- **C3 (Confirmed, F4).** When a project with unfinished tasks is completed, those tasks are archived with it as **not done** (T8), so the history is kept. Nothing is moved to the Inbox.
- **C4 (Confirmed, F5).** There is an **Inbox**. It is a **list**: the temporary place a new task goes when it isn't put in another list or project. Each task belongs to exactly one container: a list (the Inbox included) or a project.
- **C5 (Confirmed, G3).** The Inbox is built in. It can't be deleted.
- **C6 (Proposed).** As with subtasks (S10), completing a project with open tasks shows a "Mark all done" banner.

### Notes

- **N1 (Confirmed).** A task can have any number of notes.
- **N2 (Confirmed).** Notes can also **stand alone in a list or a project**.

### Reminders

- **R1 (Confirmed).** A task can have any number of reminders, but **exactly one main reminder**, which is the base.
- **R2 (Confirmed).** Each reminder is either a **sticky notification** or an **alarm**.
- **R3 (Confirmed, as Claude interpreted it and the user accepted).** The other reminders are set relative to the main reminder, for example "1 day before main". When the main reminder moves, they all move with it.
- **R4 (Proposed).** The main reminder is set relative to the task's **do date**: the start date, or the deadline if there is no start date. Examples are "on the day at 9:00" and "30 minutes before".
- **R5 (Confirmed, G1, not objected to).** No reminder is tied to the deadline. All reminders follow the do date.
- **R6 (Proposed).** A sticky reminder is a Lock Screen Live Activity scheduled for the reminder time, plus a time-sensitive notification that repeats until acted on. A suggested default is every 10 minutes, up to 6 times. See ARCHITECTURE §4.3 for why both are used.
- **R7 (Proposed).** An alarm rings through Silent mode and Focus using AlarmKit. Its secondary button is **Done**, which completes the task straight from the ringing alarm.
- **R8 (Proposed).** If a reminder is added to an undated task, the reminder's time becomes the task's start date.
- **R9 (Proposed).** If the main reminder is removed, the earliest remaining reminder becomes the main one, and every remaining reminder keeps its time.
- **R10 (Proposed).** If the do date is a whole day with no time, reminders that count minutes from it ("30 minutes before") count from 09:00.

### Rescheduling

- **D1 (Confirmed).** Rescheduling **never changes the task's plan**. It sets a temporary **override** of the do date.
- **D2 (Confirmed).** All reminders follow the override automatically. No reminder needs to be edited by hand.
- **D3 (Confirmed, F7).** If the override's day ends and the task is not done:
  - a **one-off** task stays at the new date and shows as **overdue since that date**. Its original plan is kept unchanged.
  - a **recurring** task goes back to its schedule. The occurrence shows as overdue since its planned date (T7).
- **D4 (Confirmed, F6, G1).** Rescheduling moves the **do date**. When the new date is later than the deadline, the user can **move the deadline in the same step**, quickly. The app never guesses a new deadline. The user's words: "life happens".
- **D5 (Confirmed, F7).** An override runs out at the **end of its day**, local time. Completing the task clears it. For a recurring task, the override applies only to the current occurrence.
- **D6 (Proposed).** One-tap presets: **Tonight** (19:00), **Tomorrow** and **Next week** (+7 days from today), both at the task's time of day, or as a whole day if it has none, and **Pick…**. These are offered on notifications, Live Activities, widgets and in the app.
- **D7 (Proposed).** In the Pick… sheet and in the app, a new date past the deadline shows the deadline right below it, with **Same day**, **Pick…** and **Keep**. The one-tap presets on notifications, widgets and Siri move only the do date. The task is then marked **past deadline**.
- **D8 (Proposed).** A deadline moved while rescheduling is stored with the override, like the do date, so the plan stays unchanged (D1). For a recurring task it applies to that occurrence only.

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
