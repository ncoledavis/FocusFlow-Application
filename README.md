# FocusFlow

An iOS app that helps people with ADHD work on a schedule by showing one task at a time, giving each task a clear time budget and target finish, letting a trusted supporter help manage the list, and surfacing calendar context. Built with SwiftUI + MVVM, targeting iOS 17+.

See [PROJECT_PLAN.md](PROJECT_PLAN.md) for the full product plan, architecture, and task breakdown.

## Status

- **Task 1 — Project scaffold and architecture skeleton: complete.**
- **Task 2 — Firebase integration and authentication: code complete.** The full sign-up / sign-in / sign-out flow builds, runs, and is covered by tests. A few console steps remain on the developer side (see [Firebase setup](#firebase-setup)).
- **Task 3 — Task data layer with Firestore: code complete.** Signed-in users get a live task list backed by Firestore (or an in-memory mock without the plist). Needs a Firestore database and the rules in `firestore.rules` for the live backend (see [Task 3](#task-3--task-data-layer-with-firestore)).
- **Task 4 — One-at-a-time focus view with time model: code complete.** The Focus tab shows the top task with a live countdown, and Done / Skip advance to the next. The add form supports a time budget or a fixed time slot. Overdue prompts and notifications are Task 5.

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

Once the plist is present, `FirebaseConfig` configures Firebase at launch and the app uses `FirebaseAuthService` automatically. In DEBUG builds it logs `Firebase configured ✓` so you can confirm the plist was picked up.

## Project structure

```
FocusFlow/
  App/          FocusFlowApp.swift (entry point), FirebaseConfig.swift (conditional Firebase startup)
  Views/        RootView (session router), AuthView, HomeView (Focus + Tasks tabs), FocusView, FocusCardView,
                CountdownRingView, CountdownFormatter, TaskListView, AddTaskView, ErrorBanner
  ViewModels/   AuthViewModel, SessionViewModel, TaskListViewModel, FocusViewModel, ErrorMessage
  Models/       Enums, AppUser, TaskItem, SupporterLink, CalendarEvent
  Services/     Protocols: AuthService (+ AuthError), TaskRepository, LinkRepository, CalendarProvider
  Adapters/     FirebaseAuthService, MockAuthService, FirestoreTaskRepository, MockTaskRepository (EventKit/Google adapters — later tasks)
  Resources/    GoogleService-Info.plist goes here (gitignored; download from the Firebase console)
FocusFlowTests/ Model Codable, TaskItem time model, AuthViewModel/session, TaskListViewModel, FocusViewModel, countdown formatter, Firestore mapping tests
firestore.rules Interim Firestore security rules (owner-only tasks)
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

The interim rules let each user read and write only their own tasks (`ownerUid == request.auth.uid`). Supporter access is added in Task 6.9.

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
- Firestore write calls complete when the server acknowledges them, so while offline `Add` waits until the connection returns (the local list still updates immediately). Offline handling is part of Task 9.7.
- The add form only creates duration tasks for now; fixed time slots come in Task 4.4. _(Done in Task 4.)_

### Problems encountered and how they were resolved

Nothing failed to compile and no tests failed this time. These are the issues that came up and how each was handled.

**8. A new Firestore database blocks every request.** Production-mode Firestore denies all reads and writes until rules are published, so the task list would fail on the first live run with an unhelpful error.
- *Resolution:* added an interim owner-only `firestore.rules` to paste into the console, and made `TaskListViewModel` turn Firestore's permission-denied error (code 7) into a message that points at the security rules.

**9. Field name mismatch with the plan's schema.** The model stores the explicit finish time as `storedTargetFinishAt` (the computed `targetFinishAt` is derived), but the plan's Firestore schema calls the field `targetFinishAt`. Saving the property name as-is would have made the stored data disagree with the plan and with the Task 6 security rules.
- *Resolution:* added explicit `CodingKeys` on `TaskItem` so it is persisted as `targetFinishAt`, and added tests that check the persisted key and that the computed finish is never written.

**10. Firestore writes wait for the server.** `setData` and `delete` only complete once the server acknowledges them, so while offline the Add button would wait even though the local list already shows the new task.
- *Resolution:* not fixed in this task. Documented under Known limitations and left for the offline pass in Task 9.7.

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

## Task 4 — One-at-a-time focus view with time model (Branch 4)

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
- Starting a task's clock is a saved write, so the focus screen should only run on the owner's device. The supporter views in Task 6 use the list, not this screen.

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

These are estimates of equivalent hands-on time, like the earlier tasks.

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

## Notes for the next task

Task 5 (overdue handling and notifications) builds on this screen: a `NotificationService` that schedules a local notification at `targetFinishAt`, an in-app "overdue" state when the countdown reaches zero, the "Add more time / Mark done / Skip" prompt, and "Add more time" extending `targetFinishAt` (which `allottedInterval` and the ring already handle). The "time's up" display and `TaskItem.isOverdue` are ready for it.


