# FocusFlow

An iOS app that helps people with ADHD work on a schedule by showing one task at a time, giving each task a clear time budget and target finish, letting a trusted supporter help manage the list, and surfacing calendar context. Built with SwiftUI + MVVM, targeting iOS 17+.

See [PROJECT_PLAN.md](PROJECT_PLAN.md) for the full product plan, architecture, and task breakdown.

## Status

- **Task 1 — Project scaffold and architecture skeleton: complete.**
- **Task 2 — Firebase integration and authentication: code complete.** The full sign-up / sign-in / sign-out flow builds, runs, and is covered by tests. A few console steps remain on the developer side (see [Firebase setup](#firebase-setup)).
- **Task 3 — Task data layer with Firestore: code complete.** Signed-in users get a live task list backed by Firestore (or an in-memory mock without the plist). Needs a Firestore database and the rules in `firestore.rules` for the live backend (see [Task 3](#task-3--task-data-layer-with-firestore)).
- **Task 4 — One-at-a-time focus view with time model: code complete.** The Focus tab shows the top task with a live countdown, and Done / Skip advance to the next. The add form supports a time budget or a fixed time slot. Overdue prompts and notifications are Task 5.
- **Task 5 — Overdue handling and notifications: code complete.** When a task's time runs out the app shows a "Still working on this?" prompt (Add more time / Mark done / Skip) and a "Time's up" notification fires if the app isn't open. Real notification delivery still needs a manual check on your device.
- **Task 6 — Supporter linking: code complete.** An owner can invite a supporter with a one-time code, and the supporter joins by entering it. Both sides see the link, and the owner can change the permission or remove the supporter (see [Task 6](#task-6--supporter-linking-task-6)).
- **Task 7 — Role-based permissions: code complete.** A supporter sees and works on the owner's list within the permission they were given (view / add / edit priority and order), enforced in the app and in the Firestore rules. **Publish the updated `firestore.rules` before using the live backend** (see [Task 7](#task-7--role-based-permissions-task-6)).

## Getting started

### Prerequisites

- Xcode 16+ with the iOS 17+ SDK (developed against Xcode 26 / iOS 26.5 simulator)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — generates the Xcode project from `project.yml`
- [SwiftLint](https://github.com/realm/SwiftLint) — linting

The Firebase SDK (FirebaseAuth + FirebaseFirestore, pinned to 13.x) is pulled automatically via Swift Package Manager when the project is generated — no manual install needed.

### Firebase setup

The app compiles and runs without any Firebase configuration: when no `GoogleService-Info.plist` is bundled, it falls back to an in-memory `MockAuthService`, so the full auth flow is demoable immediately. To connect the live backend:

1. Create a Firebase project in the [console](https://console.firebase.google.com/) and register an iOS app with bundle id `com.focusflow.app`.
2. Enable **Email/Password** sign-in under Authentication → Sign-in method.
3. Download `GoogleService-Info.plist` and add it to `FocusFlow/Resources/` (then re-run `xcodegen generate`). The file is gitignored, so each developer downloads their own copy; a fresh clone without it runs on the mock backends.

4. Create a Firestore database (Build → Firestore Database) and publish [`firestore.rules`](firestore.rules) (Rules tab → paste → Publish). Re-publish it whenever that file changes; supporter features need the Task 7 version.

Once the plist is present, `FirebaseConfig` configures Firebase at launch and the app uses `FirebaseAuthService` automatically. In DEBUG builds it logs `Firebase configured ✓` so you can confirm the plist was picked up.

## Project structure

```
FocusFlow/
  App/          FocusFlowApp.swift (entry point), FirebaseConfig.swift (conditional Firebase startup)
  Views/        RootView (session router), AuthView, HomeView (Focus / Tasks / Support tabs), FocusView, FocusCardView,
                CountdownRingView, CountdownFormatter, OverduePromptView, TaskListView, AddTaskView, ErrorBanner,
                SupportView, InviteSupporterView, JoinWithCodeView, SupportedOwnerTasksView
  ViewModels/   AuthViewModel, SessionViewModel, TaskListViewModel, TaskListAccess, FocusViewModel,
                SupportLinksViewModel, ErrorMessage
  Models/       Enums, AppUser, TaskItem, SupporterLink, InviteCode, CalendarEvent
  Services/     Protocols: AuthService (+ AuthError), TaskRepository, LinkRepository, CalendarProvider, NotificationService
  Adapters/     FirebaseAuthService, MockAuthService, FirestoreTaskRepository, MockTaskRepository,
                FirestoreLinkRepository, MockLinkRepository, UserNotificationService, MockNotificationService
                (EventKit/Google adapters — later tasks)
  Resources/    GoogleService-Info.plist goes here (gitignored; download from the Firebase console)
FocusFlowTests/ Model Codable, TaskItem time model, AuthViewModel/session, TaskListViewModel, FocusViewModel (incl. expiry and notifications), countdown formatter, notification service, invite codes, support links, task-list access, Firestore mapping tests
firestore.rules Firestore security rules for tasks, links and invites
firebase.json   Points the Firebase emulator at firestore.rules
firestore-tests/ Node tests that run the rules against the local Firestore emulator
project.yml     XcodeGen project spec (incl. Firebase SPM dependency)
.swiftlint.yml  Lint configuration
```

The project uses XcodeGen so the Xcode project is reproducible and defined in a readable spec rather than a hand-edited `.pbxproj`. Run `xcodegen generate` any time the file layout or targets change.

---

## Task 1 — Project scaffold and architecture skeleton B(Branch 1)

Roughly **3 hours** of work. The result: the app builds, launches to a placeholder screen on the simulator, and the full domain model + architecture skeleton is in place and tested.

### What was built

**Tooling and project setup**
- Created the XcodeGen spec (`project.yml`) defining the `FocusFlow` app target (iOS 17 deployment, bundle id `com.focusflow.app`) and the `FocusFlowTests` unit-test target.
- Added a SwiftLint configuration (`.swiftlint.yml`) with sensible line-length, body-length, and opt-in rules.
- Added a `.gitignore` covering DerivedData, build output, user Xcode state, and the generated `.xcodeproj`.
- Laid out the architecture folders: `App`, `Views`, `ViewModels`, `Models`, `Services`, `Adapters`, `Resources`.

**Domain model (`Models/`)**
- **Enums** — `Priority` (low/medium/high/urgent, `Comparable` for task selection), `TaskStatus` (pending/current/done/skipped), `ScheduleType` (duration/fixed), `LinkPermission` (view/add/edit, `Comparable` with `canView`/`canAdd`/`canEdit` helpers), `LinkStatus` (pending/active).
- **`AppUser`**, **`TaskItem`**, **`SupporterLink`** — `Codable` structs mirroring the planned Firestore documents.
- **`CalendarEvent`** — a provider-agnostic event shape shared across the (future) EventKit, Google, and mock calendar adapters.
- **`TaskItem` time model** (computed properties):
  - `targetFinishAt` — a stored finish time takes precedence (fixed slots, or a duration task whose time was extended); otherwise it is derived from `startAt + durationMinutes`.
  - `timeRemaining(asOf:)` — seconds until finish; positive while time is left, negative once overdue.
  - `isOverdue(asOf:)` — true only for an active task whose budget has elapsed.

  This math underpins the live countdown (Task 4) and the overdue prompt (Task 5).

**Service boundaries (`Services/`)** — protocol definitions only, so the concrete Firebase/EventKit/Google/mock implementations can be swapped in later and the view models can be tested against mocks:
- `AuthService` — sign up / sign in / sign out, current-user publisher.
- `TaskRepository` — create/update/delete and a real-time `observeTasks(forOwner:)` stream.
- `LinkRepository` — invite/accept/update-permission/revoke and an `observeLinks(forUser:)` stream.
- `CalendarProvider` — request access and fetch events in a date interval.

**App shell (`App/`, `Views/`)**
- `FocusFlowApp` — the SwiftUI app entry point.
- `RootView` — the placeholder root screen (replaced by the session router in Task 2).

### What was tested

**`ModelCodableTests` (6 tests)** — round-trips each model through JSON encode/decode and asserts equality, protecting the on-the-wire shape before Firestore is wired up:
- `AppUser`, `TaskItem` (duration variant), `TaskItem` (fixed variant), `SupporterLink`, `CalendarEvent`
- Raw-value round-trips for every enum

**`TaskItemTimeTests` (8 tests)** — covers the computed time model and ordering logic:
- Target finish derived from duration; stored finish takes precedence; fixed schedule uses the stored finish; a duration task with no start has no finish.
- `timeRemaining` is positive before the deadline and negative after.
- `isOverdue` is true only when the task is active and its time has elapsed (a completed task is never overdue).
- `Priority` sorts low → urgent; `LinkPermission` capability flags and ordering behave correctly.

**Verification** — `xcodebuild test` passed 14/14 on the simulator, the app launched without crashing, and `swiftlint lint` reported 0 violations.

### Problems encountered and how they were resolved

**1. No iOS simulator runtime installed.** The machine had the iOS SDK but no simulator runtime, so `xcodebuild` reported no eligible destinations and no simulator devices existed.
- *Resolution:* downloaded the iOS 26.5 simulator platform with `xcodebuild -downloadPlatform iOS`, then created a device with `xcrun simctl create`. While that large download ran, the source was verified independently with `swiftc -typecheck` against the simulator SDK.

**2. Optional `TimeInterval` passed to `XCTAssertEqual(accuracy:)`.** `timeRemaining(asOf:)` returns `TimeInterval?`, but the accuracy overload requires a non-optional `Double`, so the test target failed to compile.
- *Resolution:* unwrapped the value with `try XCTUnwrap(...)` and marked the test method `throws`.

**3. Date precision lost in Codable round-trips.** Two `TaskItem` round-trip tests failed even though the printed structs looked identical: those tests let `createdAt` default to `Date()` (sub-second precision), and ISO 8601 encoding truncates to whole seconds, so the decoded value differed by microseconds and failed `Equatable`.
- *Resolution:* gave those tests explicit whole-second timestamps. Worth remembering when Firestore serialization is added in Task 3.

**4. SwiftLint config placement warning.** SwiftLint warned that `unused_import` should live under `analyzer_rules`, not `opt_in_rules`.
- *Resolution:* moved `unused_import` into an `analyzer_rules` section; lint now runs with zero warnings.

### Effort Timeline 3 hours

| Sub-task | Work | Est. time |
| --- | --- | --- |
| 1.1 | New Xcode project (XcodeGen spec, iOS 17 target, app + test targets) | 20 min |
| 1.2 | Top-level folders/groups (Views, ViewModels, Models, Services, Adapters, Resources, Tests) | 10 min |
| 1.3 | SwiftLint setup and `.swiftlint.yml` configuration | 15 min |
| 1.4 | Define enums (Priority, TaskStatus, ScheduleType, LinkPermission, LinkStatus) | 20 min |
| 1.5 | Define Codable model structs (AppUser, TaskItem, SupporterLink) | 25 min |
| 1.6 | TaskItem computed time model (targetFinishAt, timeRemaining, isOverdue) | 25 min |
| 1.7 | Service protocols (AuthService, TaskRepository, LinkRepository, CalendarProvider) | 15 min |
| 1.8 | App entry point and placeholder root view | 10 min |
| 1.9 | Unit tests for Codable round-trips and time-model logic | 25 min |
| — | Build/test/lint verification and fixing the issues found | 15 min |
| **Total** | | **3 hours** |

---

## Task 2 — Firebase integration and authentication (Branch 2)

The result: a complete email/password auth flow — sign up, sign in, sign out, a session router, and session restoration — that builds, runs, and is fully tested against a mock backend, ready to flip to live Firebase the moment the console config is dropped in.

### What was built

**Firebase + SPM**
- Added the Firebase SDK via Swift Package Manager in `project.yml`, pulling **only** `FirebaseAuth` and `FirebaseFirestore` (pinned to the 13.x range), per the plan.
- `FirebaseConfig` configures Firebase at launch and reports whether it's configured. In DEBUG it logs either `Firebase configured ✓` or a "plist not found, using mock" message. This keeps the app buildable and runnable before any console setup.

**Auth service layer**
- `AuthService` protocol finalized with `signUp`, `signIn`, `signOut`, a synchronous `currentUser`, and a `currentUserPublisher`.
- `AuthError` — a domain error enum with user-facing messages, so the UI and tests never depend on Firebase error types.
- `FirebaseAuthService` — conforms to `AuthService`, maps Firebase `User` → `AppUser` and `AuthErrorCode` → `AuthError`, and publishes session changes via an auth-state listener (which also restores the session on relaunch).
- `MockAuthService` — in-memory account store for previews and tests, with an injectable `nextError` for exercising failure paths.

**View models and views**
- `AuthViewModel` (`@MainActor`) — holds email/password/mode state, validates input (email format + 6-char password) before calling the service, toggles between sign-in and sign-up, and exposes loading and error state.
- `SessionViewModel` — observes `currentUserPublisher` and drives the app's signed-in/out state.
- `AuthView` — a single adaptive login/sign-up form with inline validation, error banner, loading indicator, and a mode toggle.
- `HomeView` — a placeholder signed-in landing screen with a sign-out action (the task list replaces it in Task 3).
- `RootView` — the session router: shows `AuthView` when signed out and `HomeView` when signed in.

### What was tested

**`AuthViewModelTests` (11 tests)** — runs entirely against `MockAuthService`, so no Firebase or network is needed:
- Email validation (valid/invalid formats) and form validity (requires email + 6-char password).
- Sign-up success signs the user in; sign-in success restores the seeded account.
- Bad credentials surface the right error: wrong password, unknown user, duplicate email, invalid email blocked before the service is even called.
- Sign-out clears the session.
- `SessionViewModel` tracks auth state across sign-up and sign-out.
- Toggling between sign-in and sign-up clears any existing error.

**Verification** — `xcodebuild test` passed 25/25 on the simulator (14 Task 1 + 11 Task 2), the app installed and launched using the mock backend without crashing, and `swiftlint lint` reported 0 violations.

### Problems encountered and how they were resolved

**5. Building without Firebase configuration.** Firebase normally expects a `GoogleService-Info.plist` and a `FirebaseApp.configure()` call at launch, but that file comes from the console and isn't available yet. A naive setup would crash on launch or fail to build.
- *Resolution:* `FirebaseConfig` only configures Firebase when the plist is bundled, and the app selects `FirebaseAuthService` vs. `MockAuthService` accordingly. The whole auth flow builds, runs, and is testable before any console work.

**6. Async Combine delivery broke a session test.** `SessionViewModel` subscribes with `.receive(on: DispatchQueue.main)`, so session updates arrive on the next main-queue turn. A test asserted `isSignedIn` synchronously right after `signOut()` and failed because the Combine sink hadn't run yet — a test-timing bug, not a logic bug.
- *Resolution:* added a small `waitForMainQueue()` helper (fulfilled from a `DispatchQueue.main.async` block) so the test lets the run loop turn before asserting. Kept the `.receive(on:)` hop in the view model since it's the correct behavior for the Firebase listener.

**7. Two SwiftLint warnings in the new UI code.** A long `print` line in `FirebaseConfig` exceeded the line-length limit, and the submit `Button(action:){...}` tripped the multiple-trailing-closure rule.
- *Resolution:* split the log string across two lines and switched the button to the explicit `Button { } label: { }` form. Lint is back to zero violations.

### Effort Timeline 3 hours

| Sub-task | Work | Est. time |
| --- | --- | --- |
| 2.2 | Add Firebase via SPM (FirebaseAuth + FirebaseFirestore), pin version, resolve packages | 20 min |
| 2.3 | `FirebaseConfig` conditional startup + wiring in the app entry point | 15 min |
| 2.5 | Finalize the `AuthService` protocol and add the `AuthError` domain type | 15 min |
| 2.6 | Implement `FirebaseAuthService` (user + error mapping, auth-state listener) | 30 min |
| 2.7 | Build `AuthViewModel` (form state, validation, error handling) + `SessionViewModel` | 25 min |
| 2.8 / 2.9 | Build `AuthView` (login + sign-up in one adaptive form) and `HomeView` | 30 min |
| 2.10 | Build the `RootView` session router | 10 min |
| 2.11 | `MockAuthService` + `AuthViewModel`/session tests (success, bad creds, sign-out) | 20 min |
| — | Build/test/lint verification and fixing the issues found | 15 min |
| **Total** | | **3 hours** |

---

## Task 3 — Task data layer with Firestore (Branch 3)

The result: a signed-in user can add tasks and see them appear immediately in a live, priority-sorted list. Tasks are stored in Firestore with a real-time listener; without a plist the same UI runs against an in-memory mock.

### Firestore setup for this task

A new Firestore database in production mode denies all reads and writes, so the task list will show a "Permission denied" message until you:

1. Console → **Build → Firestore Database → Create database** (production mode is fine).
2. Open the **Rules** tab, paste the contents of [`firestore.rules`](firestore.rules), and **Publish**.

The interim rules let each user read and write only their own tasks (`ownerUid == request.auth.uid`). Supporter access is added in Task 7.3.

### What was built

**Data layer**
- `TaskRepository` protocol (create, update, delete, `observeTasks(forOwner:)`) plus a `TaskRepositoryError.notFound` error.
- `FirestoreTaskRepository` — writes with `setData`, deletes by ID, and observes `tasks` where `ownerUid == uid` through a snapshot listener wrapped in a Combine publisher. Each subscriber gets its own listener, which is removed on cancel or completion. Malformed documents are skipped (and logged in DEBUG) instead of breaking the stream.
- `MockTaskRepository` — in-memory store with injectable write and observe errors. It is also the app's fallback when no plist is bundled.
- **Schema (3.1):** the field table is documented on `FirestoreTaskRepository`. Dates are stored as Firestore `Timestamp`s, and `TaskItem.storedTargetFinishAt` is persisted as `targetFinishAt` to match the plan's schema (via `CodingKeys`). The computed finish time is never stored.

**View model and UI**
- `TaskListViewModel` — subscribes to the repository; exposes `activeTasks` and `finishedTasks` sorted by priority (high to low), then manual `order`, then creation time; validates and creates tasks (trimmed title, positive duration); updates, changes priority, and deletes; surfaces errors, including a readable message for Firestore permission-denied.
- `TaskListView` — "Up next" and "Finished" sections, swipe-to-delete, a context menu to change priority or delete, loading and empty states, and a dismissible error banner.
- `AddTaskView` — title, notes, priority, and a time budget stepper (5 to 240 min). Fixed time slots arrive with the hybrid schedule form in Task 4.
- `HomeView` now hosts the task list; `RootView` and `FocusFlowApp` pass the repository through (Firestore with a plist, mock without).

### What was tested

**52 tests, all passing** (25 earlier + 27 new).

**`TaskListViewModelTests` (18 tests)**, against `MockTaskRepository`:
- Only the owner's tasks load; loading state clears after the first snapshot; observation errors surface and stop loading.
- Sort order by priority, then `order`, then creation time; active and finished tasks are separated.
- Add: appears in the live list, trims title and notes, blank notes stored as `nil`, new tasks land last within their priority, blank title and zero duration are rejected, repository errors surface, and a later success clears the old error.
- Update and priority change (including the list re-sorting), update and delete of a missing task, and delete.

**`FirestoreTaskMappingTests` (9 tests)**, no network or project needed:
- Full-field round trip; sub-second date precision is preserved (the Task 1 ISO 8601 truncation issue does not apply to Timestamps).
- `targetFinishAt` is the persisted key and `storedTargetFinishAt` never appears; enums are stored as raw strings; `nil` optionals are omitted; computed finish times are not persisted.
- The document ID is authoritative for `id`, and a malformed document throws.

**Also verified:** `swiftlint lint` reports 0 violations, and the app launches on the simulator with the plist present and stays running with no crash report.

**Not verified:** reads and writes against a real Firestore database. That needs a signed-in user, the database, and the published rules, so the live path (`FirestoreTaskRepository` talking to the server and the security rules) has only been checked through the mapping tests and compilation.

### Known limitations
- Firestore write calls complete when the server acknowledges them, so while offline `Add` waits until the connection returns (the local list still updates immediately). Offline handling is part of Task 10.7.
- The add form only creates duration tasks for now; fixed time slots come in Task 4.4. _(Done in Task 4.)_

### Problems encountered and how they were resolved

Nothing failed to compile and no tests failed this time. These are the issues that came up and how each was handled.

**8. A new Firestore database blocks every request.** Production-mode Firestore denies all reads and writes until rules are published, so the task list would fail on the first live run with an unhelpful error.
- *Resolution:* added an interim owner-only `firestore.rules` to paste into the console, and made `TaskListViewModel` turn Firestore's permission-denied error (code 7) into a message that points at the security rules.

**9. Field name mismatch with the plan's schema.** The model stores the explicit finish time as `storedTargetFinishAt` (the computed `targetFinishAt` is derived), but the plan's Firestore schema calls the field `targetFinishAt`. Saving the property name as-is would have made the stored data disagree with the plan and with the Task 6 security rules.
- *Resolution:* added explicit `CodingKeys` on `TaskItem` so it is persisted as `targetFinishAt`, and added tests that check the persisted key and that the computed finish is never written.

**10. Firestore writes wait for the server.** `setData` and `delete` only complete once the server acknowledges them, so while offline the Add button would wait even though the local list already shows the new task.
- *Resolution:* not fixed in this task. Documented under Known limitations and left for the offline pass in Task 10.7.

**11. Couldn't read the startup log during the launch check.** Capturing the app's console output from `simctl` came back empty, most likely because `print` output is buffered when piped and the app was terminated before it flushed. That means I did not see the `Firebase configured ✓` line.
- *Resolution:* switched to checking that the app process is still running after startup and that no new crash report was written. Both passed, but the log line itself remains unconfirmed until you run it from Xcode.

**12. The plist was tracked in git.** The README said `GoogleService-Info.plist` was not committed, but it was.
- *Resolution:* added it to `.gitignore` and untracked it with `git rm --cached` (the local file is untouched, so the app still uses live Firebase). It remains in earlier commits' history; see the note below.

  The plist holds project identifiers and a client API key rather than a password, and every shipped iOS app contains it. If you want to limit exposure anyway, restrict that API key to your bundle ID in the Google Cloud console (APIs & Services → Credentials). Rewriting git history to purge the file isn't needed for that and I haven't done it.

### Effort Timeline 3 hours

These are estimates of equivalent hands-on time, like the earlier tasks.

| Sub-task | Work | Est. time |
| --- | --- | --- |
| 3.1 | Design the `tasks` schema, document the fields, map `targetFinishAt` with `CodingKeys` | 20 min |
| 3.2 | Finalize the `TaskRepository` protocol and add `TaskRepositoryError` | 10 min |
| 3.3 | `FirestoreTaskRepository` create / update / delete | 15 min |
| 3.4 | Real-time snapshot listener wrapped in Combine, plus document-to-`TaskItem` mapping | 25 min |
| 3.5 | `TaskListViewModel` (subscription, sorting, add / update / delete, validation, errors) | 30 min |
| 3.6 | `TaskListView`, `AddTaskView`, and wiring through `HomeView` / `RootView` / app entry | 35 min |
| 3.7 | `MockTaskRepository` and 27 new tests (view model and Firestore mapping) | 30 min |
| — | Interim security rules, build / lint / launch verification | 15 min |
| **Total** | | **3 hours** |

_Creating the Firestore database and publishing the rules are manual console steps and aren't counted in build time._

---

## Task 4 — One-at-a-time focus view with time model (Task-4)

The result: the app opens on a Focus tab that shows one task at a time, with its priority, notes, the time given, a finish time, and a clock-style countdown that ticks every second. Done and Skip mark the task and bring up the next one. The add form now offers either a time budget or a fixed time slot. The full list moved to a second tab.

### What was built

**Current-task selection and the clock (4.1)**
- `FocusViewModel.selectCurrent(from:)` picks the task to show. A task already marked `current` wins, so a newly added urgent task doesn't pull the user away mid-task. Otherwise it's the highest-priority pending task, then manual `order`, then oldest first (the same sort as the list, via `TaskListViewModel.sorted`).
- When a pending task becomes current, the view model saves `status = current` and, for duration tasks, `startAt = now`. Because the start time is stored, the countdown survives a relaunch and doesn't reset. Fixed slots keep their own start and finish.
- The clock is injectable, so tests control "now".

**Focus screen (4.2, 4.3)**
- `FocusCardView` — priority, title, notes, the countdown ring, "N min given", "Finish by …", "N more tasks up next", and large Skip / Done buttons pinned to the bottom.
- `CountdownRingView` — a ring that drains as time runs out, with `MM:SS` (or `H:MM:SS`) in the middle. When time is up it fills red, shows overtime as `+02:15`, and says "Time's up", so the state isn't conveyed by color alone. VoiceOver reads a spoken form ("12 minutes, 30 seconds remaining") instead of the ticking digits.
- `FocusView` wraps the card in a one-second `TimelineView` and shows loading and "All caught up" states. `CountdownFormatter` does the text formatting.
- `HomeView` is now a two-tab view: **Focus** and **Tasks**. The empty Focus state has a "Go to Tasks" button.

**Hybrid schedule (4.4)**
- `AddTaskView` has a "Time budget / Fixed time" picker. Time budget uses the minutes stepper; Fixed time shows start and finish date pickers (default: the next quarter hour, 30 minutes long) and keeps the finish after the start.
- `TaskListViewModel.addTask` now takes a `schedule:` (`.duration(minutes:)` or `.fixed(start:finish:)`) and rejects a finish that isn't after the start. Fixed tasks store `startAt` and `targetFinishAt` and no `durationMinutes`.
- `TaskItem.allottedInterval` gives the total time given (finish minus start when both exist, otherwise the budget). It drives the ring's progress and the "given" label, and it stays correct once "add more time" extends a finish in Task 5.
- List rows show a fixed task's time range and an "In progress" tag on the current task.

**Done and Skip (4.5, 4.6)**
- Each marks the current task (`done` or `skipped`), then waits for the next task to be started so the next card appears already running. The buttons are disabled while a write is in flight, and a failed write keeps the current task and shows the error.

**Small refactors:** a shared `ErrorBanner` view and `ErrorMessage` helper replaced the copies in the task list screen and view model.

### What was tested

**94 tests, all passing** (52 earlier + 42 new).

**`FocusViewModelTests` (25 tests)**, against `MockTaskRepository` with an injected clock:
- Selection: highest priority wins; ties break by `order`, then creation time; an in-progress task beats a higher-priority pending one; done and skipped tasks are ignored; other owners' tasks are ignored; a new urgent task doesn't interrupt the current one; "up next" count.
- Starting: the pending task becomes current with `startAt` stamped; fixed slots keep their times; an in-progress task keeps its original start; only one task is started; a failed start shows the error and leaves the task pending.
- Time math: remaining counts down and goes negative after the deadline; the progress fraction is clamped to 0...1; an unstarted task shows its full allotment; no task gives `nil`.
- Done: marks done and advances, and the next task's clock starts at the time it becomes current; finishing the last task leaves nothing current; a failed write keeps the task; no task does nothing.
- Skip: marks skipped and advances; a failed write surfaces the error. A later action clears an old error. Stream failures surface and stop loading.

**`CountdownFormatterTests` (9)**: `MM:SS` and `H:MM:SS`, rounding up partial seconds, overtime with `+`, the exact deadline, spoken text, and allotment text.

**Also added:** 5 `TaskItem.allottedInterval` tests (unstarted, started, extended, fixed, none) and 3 fixed-schedule tests in `TaskListViewModelTests`.

**Verification:** `swiftlint lint` reports 0 violations, and the app launches on the simulator, stays running, and writes no crash report. I rendered the focus card to images and checked it by eye: the ring is 60% full for 15:00 left of 25 min, and the time's-up state fills red with `+02:15` and "Time's up". The text fits a 390pt-wide screen.

**Not verified:** driving the screens by tapping, in the simulator or against live Firestore. That needs a signed-in session, so the Done / Skip flow is covered by the view-model tests only.

### Known limitations
- When time runs out the ring turns red and keeps counting overtime, but there is no "Add more time / Mark done / Skip" prompt and no notification yet. Both are Task 5.
- A skipped task goes to the Finished section, and the UI has no way to bring it back.
- A fixed-slot task is picked by priority like any other, not by the clock, so a high-priority task scheduled for tomorrow can be shown as current today.
- Starting a task's clock is a saved write, so the focus screen should only run on the owner's device. The supporter views in Task 7 use the list, not this screen.

### Problems encountered and how they were resolved

No tests failed. These are the issues that came up and how each was handled.

**13. `Branch-4` didn't contain Task 3.** PR #3 merged into `main` with no file changes, so Task 3's code existed only on the `Task-3` branch, and `Branch-4` started from `main` without it. Task 4 depends on `TaskListViewModel` and the repositories.
- *Resolution:* stopped before changing anything and asked. After PR #4 put Task 3 on `main`, I fetched and fast-forwarded `Branch-4` to `origin/main` (no merge commit).

**14. The fast-forward deleted the local `GoogleService-Info.plist`.** Task 3 untracked the plist, and a checkout that moves past a commit that still tracked it removes the working copy.
- *Resolution:* restored the file from the earlier commit (`git show ae44ae4:…`) and confirmed it is still gitignored and has the right bundle ID. **If you pull this change on another machine, git will delete that machine's plist the same way, so keep a copy or re-download it from the Firebase console.**

**15. The first render check showed an empty card.** `ImageRenderer` can't draw `ScrollView` contents, so the images showed only the Skip / Done bar, and the "running" and "time's up" files were byte-for-byte the same size. That was a limit of the tool, not an app bug.
- *Resolution:* exposed the card's content separately from its scroll container and rendered that. The throwaway render test was deleted and not committed.

**16. The simulator refused to launch the test host ("Busy").** A transient preflight failure after repeated runs.
- *Resolution:* shut down and rebooted the simulator, then re-ran.

**17. One lint warning in the new tests.** A helper returned a 3-member tuple.
- *Resolution:* dropped the unused third member (the tests that need the clock create their own).

### Effort Timeline roughly 3.5 hours


| Sub-task | Work | Est. time |
| --- | --- | --- |
| 4.1 | `FocusViewModel`: selection, starting the clock, injectable time source | 40 min |
| 4.2 | Focus card layout, `FocusView`, and the Focus / Tasks tab view | 35 min |
| 4.3 | Countdown ring, formatter, and the one-second timeline | 30 min |
| 4.4 | Hybrid schedule: `addTask(schedule:)`, form changes, `allottedInterval`, list rows | 30 min |
| 4.5 / 4.6 | Done and Skip with advance and error handling | 15 min |
| 4.7 | 42 new tests (focus view model, formatter, `allottedInterval`, fixed schedules) | 45 min |
| — | Branch / plist recovery, visual render check, build / lint / launch verification | 20 min |
| **Total** | | **about 3.5 hours (215 min)** |

---

## Task 5 — Overdue handling and notifications (Task-5)

The result: when the current task's countdown reaches zero, a "Still working on this?" sheet appears with **Add more time**, **Mark done** and **Skip**. If the app isn't open, a "Time's up" notification fires at the finish time instead. Adding time pushes the finish out, resets the countdown and reschedules the notification.

### What was built

**Notifications (5.1, 5.2)**
- `NotificationService` protocol (`requestPermissionIfNeeded`, `scheduleExpiry`, `cancelExpiry`), with `UserNotificationService` (wraps `UNUserNotificationCenter`) and `MockNotificationService` for tests. Scheduling and cancelling are synchronous so a cancel can't overtake an earlier schedule.
- Permission is requested once, when the Focus screen starts, and re-checked whenever the app returns to the foreground, so turning notifications on in Settings is picked up. **Fallback:** if notifications are denied, the focus card shows "Notifications are off. You'll only be alerted while the app is open." with an Open Settings link, and the in-app prompt still works.
- `FocusViewModel` keeps exactly one notification in step with the running task: scheduled at its finish time when the clock starts, rescheduled when the finish changes, and cancelled when the task is marked done or skipped, when the current task changes, or when the finish has already passed. It only reschedules when the task or finish actually changes, not on every list update.
- One notification identifier per task (`task-expiry-<id>`), so rescheduling replaces the old request. Cancelling also clears a delivered notification from Notification Center.

**Detecting that time ran out (5.3)**
- `FocusViewModel.isOverdue` is set when the current task's remaining time reaches zero. It's checked on a one-second ticker owned by the view model (injectable for tests) and on every list update, so a task that expired while the app was closed is flagged as soon as it loads. Because the view model owns the ticker, it works from either tab.

**The prompt (5.4)**
- `OverduePromptView` — "Time's up", the task title, "Still working on this?", four "Add more time" options (+5, +10, +15, +30 minutes), **Mark done** and **Skip**. The three choices cover every case, so the sheet can't be swiped away.
- `HomeView` now owns the focus view model and presents the sheet, so it appears over the Focus or Tasks tab (and switches to Focus). `FocusView` receives the view model; `RootView` and `FocusFlowApp` pass the notification service down.

**Add more time (5.5)**
- `TaskItem.extended(byMinutes:from:)` counts the extra time from the later of the current finish and now, so adding 10 minutes to a task that ran out 2 minutes ago gives 10 minutes from now, not 8. The new finish is saved as the stored finish; `startAt` and `durationMinutes` are untouched.
- `FocusViewModel.addMoreTime(minutes:)` saves it. The repository re-emits the list, which clears `isOverdue` and reschedules the notification.

### What was tested

**133 tests, all passing** (94 earlier + 39 new).

**`FocusViewModelExpiryTests` (28 tests)**, with an injected clock, a hand-driven ticker and `MockNotificationService`:
- Overdue transition: not overdue while time remains; overdue at exactly zero (one second left is not); stays overdue; never overdue with no task; a task already past its finish is flagged on load without a tick; Done clears it; Skip moves to a task that isn't overdue.
- Add more time: counts from now when overdue (10 minutes from now, not 8); extends the existing finish when there is time left; keeps the task running with its original `startAt` and budget; can expire again after being extended; rejects zero or negative minutes; a failed write keeps the prompt and shows the error; no current task does nothing.
- Permission: asked once on start; denied is exposed for the fallback note; a change made in Settings is picked up on refresh; the prompt still works when denied.
- Notifications: scheduled at the finish when the task starts; not rescheduled on unrelated list changes; rescheduled after add more time; cancelled on Done and on Skip; the next task's notification is scheduled when it starts; none for a finish in the past or for an empty list; a failed Done keeps the notification.

**`UserNotificationServiceTests` (4)**: the request fires at the finish time with a non-repeating trigger, uses one identifier per task, names the task in the body, and isn't built for a finish that isn't in the future.

**`TaskItemTimeTests` (+7)**: extending before the finish, after it, at exactly the finish, with no finish yet, twice in a row, changing only the finish, and the effect on `isOverdue` and `allottedInterval`.

**End-to-end check (not committed).** I temporarily added a launch flag that signs in a demo user with mock services and a task that expires in 6 seconds, plus a UI test, and ran them on the simulator: the focus card showed, the prompt appeared when time ran out, swiping down did not dismiss it, tapping +10 dismissed it and the ring read "9 minutes, 57 seconds remaining", and Done advanced to the next task with a fresh 09:59 countdown. I viewed the screenshots. The flag, the UI test target and its scheme were then removed; the demo steps below reproduce it by hand.

**Verification:** `swiftlint lint` reports 0 violations.

**Not verified:**
- Real notification delivery. The end-to-end run used the mock notification service, so the system permission dialog and an actual banner at the finish time were not exercised. Only the request that `UserNotificationService` builds is tested.
- Add more time against live Firestore (it's covered by the mock repository and the same write path as Done and Skip).
- The prompt while another sheet (such as Add Task) is open. SwiftUI should show it once that sheet closes, but I didn't check.
- The "Notifications are off" note on a device with notifications denied.

**To try it by hand:** add a task with the minimum 5 minutes, then either leave the app open to see the prompt, or lock the device / go to the Home Screen to see the notification. The first launch asks for notification permission.

### Known limitations
- A notification isn't shown while the app is in the foreground; the prompt is the alert.
- The notification is scheduled when the app runs. If a task's clock starts or changes on another device, this device gets no notification until the app is opened.
- After adding time, the ring shows the share of the *total* time given (original plus extra), so it restarts below full. For example, a 10-minute task that ran 2 minutes over and got +10 shows "22 min given" and about 45% full. The digits always show the real time left.
- The shortest task the add form allows is 5 minutes, so seeing a real expiry takes at least that long.

### Problems encountered and how they were resolved

No unit test failed. These are the issues that came up and how each was handled.



**19. The prompt's Skip button was cut off.** The first end-to-end run passed, but the screenshot showed the sheet at its half-height setting, with Skip below the visible area. My test had only checked that the button *existed*.
- *Resolution:* the sheet now opens at 75% height (and can expand), and the test now requires the buttons to be tappable. That check initially failed for a test-side reason: there are two "Skip" buttons (the card's, hidden behind the sheet, and the prompt's), so the test now passes if any matching button is tappable.

**20. The time options wrapped unevenly.** With "+10 min" labels, "+5 min" fit on one line while "+10 / min" wrapped to two.
- *Resolution:* shortened the labels to "+5", "+10", "+15", "+30", moved the unit into the heading ("Add more time (minutes)"), and kept the VoiceOver label "Add 10 minutes".

### Effort Timeline about 3 hours 40 minutes


| Sub-task | Work | Est. time |
| --- | --- | --- |
| 5.1 | `NotificationService`, `UserNotificationService`, mock, permission request and the notifications-off note | 35 min |
| 5.2 | Notification lifecycle in `FocusViewModel` (schedule, reschedule, cancel) | 25 min |
| 5.3 | Expiry detection: injectable ticker and `isOverdue` | 25 min |
| 5.4 | `OverduePromptView`, moving the view model up to `HomeView`, wiring through `RootView` and the app | 40 min |
| 5.5 | `addMoreTime` and `TaskItem.extended` | 20 min |
| 5.6 | 39 new tests | 45 min |
| — | Branch sync and plist backup, end-to-end UI check, layout fixes, build / lint | 30 min |
| **Total** | | **about 3 hours 40 minutes (220 min)** |

---

## Task 6 — Supporter linking (Task-6)

The result: an owner can invite someone they trust with a one-time code, and that person joins by entering it. Both sides then see the link, and the owner can change what the supporter is allowed to do, or remove them, at any time. What a supporter can actually do with the owner's tasks is Task 7.

### Before using it with live Firebase

Pending invites and active links live in new Firestore collections, so the live backend needs the updated [`firestore.rules`](firestore.rules) from Task 7 published (Firebase console → Firestore Database → Rules → paste → Publish). No new indexes are needed. Without a `GoogleService-Info.plist` the app uses in-memory mocks, and the whole flow still works inside one app session: sign out, sign up as a second person, and join with the code.

### How it works

- **Two collections, because a pending invite and an active link need different security.**
  - `invites/{code}` is a pending invite. The document ID *is* the random 8-character code (about 40 bits, no `0 O 1 I L`), so only someone who has the code can fetch it. The rules don't let anyone list other people's invites, so codes can't be harvested.
  - `links/{ownerUid}_{supporterUid}` is an active link. The ID is derived from both UIDs because Firestore rules can look a document up by path but can't run queries, and the task rules (Task 7) need to find a supporter's link.
  - `LinkRepository` merges both into one `SupporterLink` type (pending or active), so the view models and screens treat them uniformly. The field tables are documented on `FirestoreLinkRepository`.
- **Accepting is one atomic batch:** create the link and delete the invite. The rules (Task 7) require both, require the link's permission to match the invite, and refuse the batch if the invite isn't consumed, so a code works once and the permission can't be upgraded.

### What was built

**Data layer (6.1 to 6.4)**
- `LinkRepository` protocol: `createInvite`, `acceptInvite`, `updatePermission(of:to:)`, `revoke(_:)`, `observeLinks`. It takes the link itself, so the repository knows whether it's an invite or an active link without parsing IDs. `LinkRepositoryError` covers invite not found, your own invite, already linked, and link not found.
- `FirestoreLinkRepository`: invite creation, accept (checks the invite, refuses your own, refuses a duplicate link, then commits the batch), permission updates, revoke, and a merged real-time stream from three listeners (my invites, my supporters, people I support).
- `MockLinkRepository` follows the same rules, so tests and the no-Firebase demo behave like the real thing.
- `InviteCode`: secure generation, cleaning up what people type or paste (any case, with or without the hyphen), validation, and the `ABCD-EFGH` display form.
- `SupporterLink` gained `ownerEmail` and `supporterEmail` so lists show an email instead of a UID. They are display-only copies and are never used for access decisions.
- `SupportLinksViewModel`: one subscription that sorts links into "people who support me", "invites I've sent" and "people I support", plus create invite, accept (with code clean-up and validation), change permission, and revoke.

**Screens (6.5, 6.6)**
- A **Support** tab (`SupportView`): "People who support me" with a "…" menu per person (change permission, remove) and a confirmation before removing; "Waiting to be accepted" for pending invites with share and cancel; "People I support" with a row per owner and "Enter an invite code".
- `InviteSupporterView`: choose a permission, create the code, then share or copy it.
- `JoinWithCodeView`: enter the code, with clear errors for a malformed, unknown, used or own code.

### What was tested

**44 new Swift tests, all passing:**
- `InviteCodeTests` (7): generated codes are valid and different, the alphabet leaves out confusing characters, normalizing and validation, formatting.
- `SupportLinksViewModelTests` (22), with an owner and a supporter view model over one repository: create an invite, accept (typed lowercase or with the hyphen), malformed / unknown / own / already-used codes, one link per pair, permission changes seen by the supporter immediately, revoke and cancel, a removed supporter needing a new invite, being an owner and a supporter at once, and unrelated people seeing nothing.
- `FirestoreLinkMappingTests` (11), `SupporterLinkTests` (4): the stored fields match what the rules require, the document ID is authoritative, pending invites map to links keyed by their code.

**End-to-end check in the real UI (not committed).** I temporarily added a launch flag that boots the app on mock services, plus a UI test, and drove two people through it on the simulator: Alice signs up and creates an invite; Bob signs up, tries a wrong code (sees the error), and joins with the right one; Alice changes Bob to View only and then removes him; Bob's "People I support" is then empty. I viewed the screenshots. The flag, the test target and its scheme were removed afterwards.

**Verification:** `swiftlint lint` reports 0 violations.

**Not verified:**
- The Swift app talking to a real Firestore project with two accounts.
- Sharing the code through the system share sheet (the buttons are there; the sheet itself wasn't opened).

### Known limitations
- Invites don't expire. A code works until it's used or the owner cancels it. An expiry time would be a sensible hardening step.
- Emails on links are display-only text written by each person's own app. Nothing relies on them, but someone could write a misleading one.
- Only the owner can end a link; a supporter can't remove themselves.

### Problems encountered and how they were resolved

**21. `Task-6` was behind `main` again.** The branch sat at the Task 4 merge and didn't have Task 5, and it had no commits of its own.
- *Resolution:* fast-forwarded it to `origin/main`. The plist stayed in place this time because neither commit tracks it.

**22. The obvious data model leaks invites.** The plan puts pending and active links in one `links` collection. For a supporter to accept by code, any signed-in user would have to be able to query pending links, which would let anyone list every pending invite and join any list. The task rules also need to find a supporter's link by path, which a random link ID doesn't allow.
- *Resolution:* the two-collection design described above (code as the invite's document ID, deterministic link IDs), with the repository hiding the split. The rules tests in Task 7 cover the invite-listing and reuse cases.

**23. A compile error in new tests.** `XCTUnwrap(await …)` isn't allowed because its argument can't be async.
- *Resolution:* await first, then unwrap.

**24. An end-to-end test step failed for a test-side reason.** Bob was inside the pushed task list, where the Sign Out button isn't shown.
- *Resolution:* the test now goes back before signing out.

### Effort Timeline 3 hours

These are estimates of equivalent hands-on time, like the earlier tasks.

| Sub-task | Work | Est. time |
| --- | --- | --- |
| 6.1 / 6.2 | Design the two-collection model, finalize `LinkRepository`, `MockLinkRepository`, link model changes | 36 min |
| 6.3 / 6.4 | `FirestoreLinkRepository` (invite, atomic accept, merged real-time stream) and `InviteCode` | 40 min |
| 6.5 | Support tab, owner's supporters list, invite sheet | 40 min |
| 6.6 | Join-with-code sheet | 13 min |
| 6.7 | 44 new tests (invite codes, link view model, Firestore mapping) | 33 min |
| — | End-to-end UI run of the linking flow, fixes, build / lint | 18 min |
| **Total** | | **3 hours (180 min)** |

---

## Task 7 — Role-based permissions (Task-6)

Task 7 was originally the second half of Task 6 and was built on the same branch. The result: the supporter sees the owner's task list with only the controls their permission allows, and the permission is enforced twice, in the app and in the Firestore security rules. The owner can change the permission or remove the supporter, and it takes effect on the supporter's screen immediately.

| Permission | Can read tasks | Can add tasks | Can change priority and order | Can edit other fields or delete |
| --- | --- | --- | --- | --- |
| View only | yes | no | no | no |
| Can add tasks | yes | yes | no | no |
| Can edit priority & order | yes | yes | yes | no |
| Owner | yes | yes | yes | yes |

### Before using it with live Firebase

The rules from Task 3 only allow people to touch their own tasks, so supporters would get "permission denied". **Publish the new [`firestore.rules`](firestore.rules)** (Firebase console → Firestore Database → Rules → paste → Publish). No new indexes are needed.

### How it works

- **Supporter edits write only `priority` and `order`.** `TaskRepository.updateOrdering` is a field-level update, which is exactly what the "edit" rule allows. It also avoids overwriting a status change made at the same moment.
- **Two layers of enforcement.** `TaskListAccess` and `TaskListViewModel` give clear messages and hide controls the person can't use. The Firestore rules are the real enforcement.

### What was built

**The supporter's view (7.1)**
- `SupportedOwnerTasksView` shows the owner's list through `TaskListView` with a role banner ("View only", "You can add tasks", …). Buttons and menu items the permission doesn't allow are hidden, and the view follows permission changes and removal live. Rows show "Added by a supporter".

**Permission enforcement in the view models (7.2)**
- `TaskListAccess`: `.owner` or `.supporter(permission)` with `canAdd`, `canReorder` and `canModify`.
- `TaskListViewModel` checks it before add, update, set priority, move and delete, and refuses with "You don't have permission to …". `access` can change while a list is open.
- New: `move(_:_:)` moves a task up or down within its priority by renumbering `order` (this also resolves ties), and `setPriority` now uses the field-level update.

**Security rules (7.3)**: [`firestore.rules`](firestore.rules) for `tasks`, `links` and `invites`, as in the table above. A supporter can create tasks only as themselves and only as `pending`; an edit supporter can change only `priority` and `order`; only the owner can delete, change a permission, or remove a link. A link can only be created by the supporter, in the same batch that consumes the invite, and its permission has to match the invite.

### What was tested

**21 new Swift tests, all passing (198 in total across Tasks 1 to 7):** `TaskListAccessTests` covers the capability table; view-only can't add, reorder, edit or delete; add can add (authored by the supporter, pending) but not reorder; edit can add and change only priority (status, start time and order stay untouched) but can't edit or delete; the owner can do everything; a downgrade or upgrade on an open list applies immediately; and move up and down, the ends, staying within one priority, ties, ignoring finished tasks, and failures.

**62 security-rule tests, all passing**, run against the local Firestore emulator (`firestore-tests/`): each permission level for reading, creating, updating and deleting; people with no link and signed-out users; link changes taking effect at once (removal, downgrade, upgrade); invite creation and cancelling; invites readable by code but not listable; accepting an invite and the many ways to cheat it (not consuming the invite, upgrading the permission, joining as someone else, accepting your own, wrong owner, wrong ID, reusing a code, no invite at all); and link reads, permission changes and removal.
- To check these tests aren't passing for the wrong reason, I broke four security-critical rules one at a time (invite not required to be consumed, edit supporters allowed to change any field, link permission not required to match the invite, anyone allowed to list invites). Each break was caught by exactly the test written for it, and the rules were restored.
- To run them: `cd firestore-tests && npm install && npm test`. This needs Node and Java; the first run downloads the Firestore emulator. The `PERMISSION_DENIED` lines in the output are the SDK logging denials the tests expect.

**End-to-end check in the real UI (not committed).** With the same temporary launch flag: an **add** supporter opens the owner's list, sees "You can add tasks", adds a task (which shows "Added by a supporter") and gets no Delete or Move options; the owner sees it. An **edit** supporter gets Move up, Move down and Change priority but not Delete, moves a task and makes it Urgent, and the owner sees both changes. I viewed the screenshots, then removed the flag and the test target.

**Verification:** `swiftlint lint` reports 0 violations.

**Not verified:**
- The Swift app talking to a real Firestore project with two real accounts. The rules were tested with documents shaped like what the app writes, and the mapping tests check the app's field names, but the two have not been exercised together.
- Supporter flows over a real network, including live updates between two devices.

### Known limitations
- Supporters can't change a task's status, so they can't mark tasks done.
- Reordering renumbers several tasks with separate writes, so a network failure partway could leave two tasks tied; the next move or the creation-time tiebreak sorts it out.
- The owner's whole-task updates (such as starting a task) and a supporter's priority change are separate writes. If they land in the same instant, the owner's write could overwrite the supporter's change.
- The rules and `TaskItem`'s stored field names depend on each other: renaming a field means updating both.

### Problems encountered and how they were resolved

**25. A full-document write could trip the "edit" rule (a risk avoided by design, not an observed failure).** The edit rule allows only `priority` and `order` to change. Re-saving a whole task from a supporter's phone could change a timestamp by a microsecond on its round trip through `Date`, and the rule would then reject the write. I did not test whether that actually happens.
- *Resolution:* `updateOrdering` writes just those two fields.

**26. The emulator refused the rules file.** `firebase emulators:exec` rejects a rules path outside its project directory.
- *Resolution:* moved `firebase.json` to the repository root, which is also where `firebase deploy` expects it.

**27. One rules test was wrong, not the rules.** I expected an owner re-saving their own invite with a different permission to be refused, but changing a pending invite's permission is meant to be allowed.
- *Resolution:* replaced it with the two cases that matter (another user taking over an existing code, and re-creating a code with other changed fields).

**28. npm skipped some install scripts.** npm 11 doesn't run package install scripts by default and warned about three.
- *Resolution:* none needed; the emulator and tests ran fine.

### Effort Timeline 3 hours

These are estimates of equivalent hands-on time, like the earlier tasks.

| Sub-task | Work | Est. time |
| --- | --- | --- |
| 7.1 | Supporter's view of an owner's list (`TaskListView` changes, role banner, live permission changes) | 25 min |
| 7.2 | `TaskListAccess`, view-model gating, move up / down, `updateOrdering` | 34 min |
| 7.3 | `firestore.rules` for tasks, links and invites | 38 min |
| — | Emulator setup, 62 rules tests, breaking rules to check the tests | 51 min |
| 7.4 | 21 new permission-gating tests | 15 min |
| — | End-to-end UI runs for add- and edit-level supporters, fixes, build / lint | 17 min |
| **Total** | | **3 hours (180 min)** |

---
