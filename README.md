# FocusFlow

An iOS app that helps people with ADHD work on a schedule by showing one task at a time, giving each task a clear time budget and target finish, letting a trusted supporter help manage the list, and surfacing calendar context. Built with SwiftUI + MVVM, targeting iOS 17+.

See [PROJECT_PLAN.md](PROJECT_PLAN.md) for the full product plan, architecture, and task breakdown.

## Status

- **Task 1 — Project scaffold and architecture skeleton: complete.**
- **Task 2 — Firebase integration and authentication: code complete.** The full sign-up / sign-in / sign-out flow builds, runs, and is covered by tests. A few console steps remain on the developer side (see [Firebase setup](#firebase-setup)).

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
3. Download `GoogleService-Info.plist` and add it to `FocusFlow/Resources/` (then re-run `xcodegen generate`).

Once the plist is present, `FirebaseConfig` configures Firebase at launch and the app uses `FirebaseAuthService` automatically.

## Project structure

```
FocusFlow/
  App/          FocusFlowApp.swift (entry point), FirebaseConfig.swift (conditional Firebase startup)
  Views/        RootView.swift (session router), AuthView.swift (login/sign-up), HomeView.swift
  ViewModels/   AuthViewModel.swift (form + validation), SessionViewModel.swift (session state)
  Models/       Enums, AppUser, TaskItem, SupporterLink, CalendarEvent
  Services/     Protocols: AuthService (+ AuthError), TaskRepository, LinkRepository, CalendarProvider
  Adapters/     FirebaseAuthService.swift, MockAuthService.swift (EventKit/Google adapters — later tasks)
  Resources/    GoogleService-Info.plist goes here (not committed)
FocusFlowTests/ Model Codable + TaskItem time-model + AuthViewModel/session tests
project.yml     XcodeGen project spec (incl. Firebase SPM dependency)
.swiftlint.yml  Lint configuration
```

The project uses XcodeGen so the Xcode project is reproducible and defined in a readable spec rather than a hand-edited `.pbxproj`. Run `xcodegen generate` any time the file layout or targets change.

## What was built in Task 1

### Tooling and project setup
- Created the XcodeGen spec (`project.yml`) defining the `FocusFlow` app target (iOS 17 deployment, bundle id `com.focusflow.app`) and the `FocusFlowTests` unit-test target.
- Added a SwiftLint configuration (`.swiftlint.yml`) with sensible line-length, body-length, and opt-in rules.
- Added a `.gitignore` covering DerivedData, build output, user Xcode state, and the generated `.xcodeproj`.
- Laid out the architecture folders: `App`, `Views`, `ViewModels`, `Models`, `Services`, `Adapters`, `Resources`.

### Domain model (`Models/`)
- **Enums** — `Priority` (low/medium/high/urgent, `Comparable` for task selection), `TaskStatus` (pending/current/done/skipped), `ScheduleType` (duration/fixed), `LinkPermission` (view/add/edit, `Comparable` with `canView`/`canAdd`/`canEdit` helpers), `LinkStatus` (pending/active).
- **`AppUser`**, **`TaskItem`**, **`SupporterLink`** — `Codable` structs mirroring the planned Firestore documents.
- **`CalendarEvent`** — a provider-agnostic event shape shared across the (future) EventKit, Google, and mock calendar adapters.
- **`TaskItem` time model** (computed properties):
  - `targetFinishAt` — a stored finish time takes precedence (fixed slots, or a duration task whose time was extended); otherwise it is derived from `startAt + durationMinutes`.
  - `timeRemaining(asOf:)` — seconds until finish; positive while time is left, negative once overdue.
  - `isOverdue(asOf:)` — true only for an active task whose budget has elapsed.

  This math underpins the live countdown (Task 4) and the overdue prompt (Task 5).

### Service boundaries (`Services/`)
Protocol definitions only, so the concrete Firebase/EventKit/Google/mock implementations can be swapped in later and the view models can be tested against mocks:
- `AuthService` — sign up / sign in / sign out, current-user publisher.
- `TaskRepository` — create/update/delete and a real-time `observeTasks(forOwner:)` stream.
- `LinkRepository` — invite/accept/update-permission/revoke and an `observeLinks(forUser:)` stream.
- `CalendarProvider` — request access and fetch events in a date interval.

### App shell (`App/`, `Views/`)
- `FocusFlowApp` — the SwiftUI app entry point.
- `RootView` — the placeholder root screen (replaced by the session router in Task 2).

## What was built in Task 2

### Firebase + SPM
- Added the Firebase SDK via Swift Package Manager in `project.yml`, pulling **only** `FirebaseAuth` and `FirebaseFirestore` (pinned to the 13.x range), per the plan.
- `FirebaseConfig` configures Firebase at launch **only if** a `GoogleService-Info.plist` is bundled, and reports whether it's configured. This keeps the app buildable and runnable before any console setup.

### Auth service layer
- `AuthService` protocol finalized with `signUp`, `signIn`, `signOut`, a synchronous `currentUser`, and a `currentUserPublisher`.
- `AuthError` — a domain error enum with user-facing messages, so the UI and tests never depend on Firebase error types.
- `FirebaseAuthService` — conforms to `AuthService`, maps Firebase `User` → `AppUser` and `AuthErrorCode` → `AuthError`, and publishes session changes via an auth-state listener (which also restores the session on relaunch).
- `MockAuthService` — in-memory account store for previews and tests, with an injectable `nextError` for exercising failure paths.

### View models and views
- `AuthViewModel` (`@MainActor`) — holds email/password/mode state, validates input (email format + 6-char password) before calling the service, toggles between sign-in and sign-up, and exposes loading and error state.
- `SessionViewModel` — observes `currentUserPublisher` and drives the app's signed-in/out state.
- `AuthView` — a single adaptive login/sign-up form with inline validation, error banner, loading indicator, and a mode toggle.
- `HomeView` — a placeholder signed-in landing screen with a sign-out action (the task list replaces it in Task 3).
- `RootView` — the session router: shows `AuthView` when signed out and `HomeView` when signed in.

## Effort estimate

### Task 1 — roughly 3 hours

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
| — | Build/test/lint verification and fixing the issues found (see below) | 15 min |
| **Total** | | **3 hours** |

### Task 2 — roughly 3 hours

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
| — | Build/test/lint verification and fixing the issues found (see below) | 15 min |
| **Total** | | **3 hours** |

_Items 2.1 and 2.4 are manual Firebase console steps and aren't counted in build time._

## What was tested

Unit tests live in `FocusFlowTests/`. **25 tests, all passing** (14 from Task 1, 11 added in Task 2).

### `ModelCodableTests` (6 tests)
Round-trips each model through JSON encode/decode and asserts equality, protecting the on-the-wire shape before Firestore is wired up:
- `AppUser`, `TaskItem` (duration variant), `TaskItem` (fixed variant), `SupporterLink`, `CalendarEvent`
- Raw-value round-trips for every enum

### `TaskItemTimeTests` (8 tests)
Covers the computed time model and ordering logic:
- Target finish derived from duration; stored finish takes precedence; fixed schedule uses the stored finish; a duration task with no start has no finish.
- `timeRemaining` is positive before the deadline and negative after.
- `isOverdue` is true only when the task is active and its time has elapsed (a completed task is never overdue).
- `Priority` sorts low → urgent; `LinkPermission` capability flags and ordering behave correctly.

### `AuthViewModelTests` (11 tests, added in Task 2)
Runs entirely against `MockAuthService`, so no Firebase or network is needed:
- Email validation (valid/invalid formats) and form validity (requires email + 6-char password).
- Sign-up success signs the user in; sign-in success restores the seeded account.
- Bad credentials surface the right error: wrong password, unknown user, duplicate email, invalid email blocked before the service is even called.
- Sign-out clears the session.
- `SessionViewModel` tracks auth state across sign-up and sign-out.
- Toggling between sign-in and sign-up clears any existing error.

### Verification performed
- `xcodebuild test` → **TEST SUCCEEDED**, 25/25 passing on the iOS simulator.
- The app was installed and launched on the simulator (using the mock backend, since no plist is present) and came up without crashing.
- `swiftlint lint` → **0 violations, 0 warnings** across all source files.

## Problems encountered and how they were resolved

### Task 1

#### 1. No iOS simulator runtime installed
The machine had the iOS **SDK** but no simulator **runtime**, so `xcodebuild` reported no eligible destinations and no simulator devices existed.

- **Resolution:** Downloaded the iOS 26.5 simulator platform with `xcodebuild -downloadPlatform iOS`, then created a device with `xcrun simctl create`. While that large download ran, the source was verified independently with `swiftc -typecheck` against the simulator SDK to confirm it compiled.

#### 2. Optional `TimeInterval` passed to `XCTAssertEqual(accuracy:)`
`timeRemaining(asOf:)` returns `TimeInterval?`, but the accuracy overload of `XCTAssertEqual` requires a non-optional `Double`, so the test target failed to compile.

- **Resolution:** Unwrapped the value with `try XCTUnwrap(...)` before the accuracy assertion and marked the test method `throws`.

#### 3. Date precision lost in Codable round-trips
Two `TaskItem` round-trip tests failed even though the printed structs looked identical. The cause: those tests let `createdAt` default to `Date()` (sub-second precision), and ISO 8601 encoding truncates to whole seconds, so the decoded value differed by microseconds and failed `Equatable`.

- **Resolution:** Gave those tests explicit whole-second timestamps, matching the other round-trip tests. Worth remembering when Firestore serialization is added in Task 3.

#### 4. SwiftLint config placement warning
SwiftLint warned that `unused_import` should live under `analyzer_rules`, not `opt_in_rules`.

- **Resolution:** Moved `unused_import` into an `analyzer_rules` section. Lint now runs with zero warnings.

### Task 2

#### 5. Building without Firebase configuration
Firebase normally expects a `GoogleService-Info.plist` and a `FirebaseApp.configure()` call at launch, but that file comes from the console and isn't available yet. A naive setup would crash on launch or fail to build.

- **Resolution:** `FirebaseConfig` only configures Firebase when the plist is bundled, and the app selects `FirebaseAuthService` vs. `MockAuthService` accordingly. The whole auth flow builds, runs, and is testable before any console work.

#### 6. Async Combine delivery broke a session test
`SessionViewModel` subscribes with `.receive(on: DispatchQueue.main)`, so session updates arrive on the next main-queue turn. A test asserted `isSignedIn` synchronously right after `signOut()` and failed because the Combine sink hadn't run yet — a test-timing bug, not a logic bug.

- **Resolution:** Added a small `waitForMainQueue()` helper (fulfilled from a `DispatchQueue.main.async` block) so the test lets the run loop turn before asserting. Kept the `.receive(on:)` hop in the view model since it's the correct behavior for the Firebase listener.

#### 7. Two SwiftLint warnings in the new UI code
A long `print` line in `FirebaseConfig` exceeded the line-length limit, and the submit `Button(action:){...}` tripped the multiple-trailing-closure rule.

- **Resolution:** Split the log string across two lines and switched the button to the explicit `Button { } label: { }` form. Lint is back to zero violations.

## Notes for the next task

Task 3 (task data layer with Firestore) builds the `FirestoreTaskRepository` against the `TaskRepository` protocol, adds a real-time listener, and wires up `TaskListViewModel` with a `MockTaskRepository` for tests. To run against the live backend you'll need the Firebase console steps above (project, Email/Password, and the `GoogleService-Info.plist`); otherwise the mock keeps everything demoable. Also remember the date-precision note from Task 1 when mapping Firestore timestamps.

## AI was used to clean up a lot fo the documentation and keep me organized on priority and next steps
