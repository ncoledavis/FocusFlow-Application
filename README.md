# FocusFlow

An iOS app that helps people with ADHD work on a schedule by showing one task at a time, giving each task a clear time budget and target finish, letting a trusted supporter help manage the list, and surfacing calendar context. Built with SwiftUI + MVVM, targeting iOS 17+.

See [PROJECT_PLAN.md](PROJECT_PLAN.md) for the full product plan, architecture, and task breakdown.

## Getting started

### Prerequisites

- Xcode 16+ with the iOS 17+ SDK (developed against Xcode 26 / iOS 26.5 simulator)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — generates the Xcode project from `project.yml`
- [SwiftLint](https://github.com/realm/SwiftLint) — linting

## Project structure

```
FocusFlow/
  App/          FocusFlowApp.swift — app entry point
  Views/        RootView.swift — placeholder root screen
  ViewModels/   (MVVM view models — added in later tasks)
  Models/       Enums, AppUser, TaskItem, SupporterLink, CalendarEvent
  Services/     Protocols: AuthService, TaskRepository, LinkRepository, CalendarProvider
  Adapters/     (Firebase / EventKit / Google / Mock implementations — later tasks)
  Resources/    (assets, Info.plist additions — later tasks)
FocusFlowTests/ Model Codable + TaskItem time-model tests
project.yml     XcodeGen project spec
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
- `RootView` — a placeholder screen so the app launches; it will be replaced by the auth-vs-main router in Task 2.

## Effort estimate

Task 1 represents roughly **3 hours** of equivalent hands-on work, broken down across the sub-tasks:

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

## What was tested

Unit tests live in `FocusFlowTests/`. **14 tests, all passing.**

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

### Verification performed
- `xcodebuild test` → **TEST SUCCEEDED**, 14/14 passing on the iOS simulator.
- The app was installed and launched on the simulator and came up without crashing.
- `swiftlint lint` → **0 violations, 0 warnings** across all 13 source files.

## Problems encountered and how they were resolved

### 1. No iOS simulator runtime installed
The machine had the iOS **SDK** but no simulator **runtime**, so `xcodebuild` reported no eligible destinations and no simulator devices existed.

- **Resolution:** Downloaded the iOS 26.5 simulator platform with `xcodebuild -downloadPlatform iOS`, then created a device with `xcrun simctl create`. While that large download ran, the source was verified independently with `swiftc -typecheck` against the simulator SDK to confirm it compiled.

### 2. Optional `TimeInterval` passed to `XCTAssertEqual(accuracy:)`
`timeRemaining(asOf:)` returns `TimeInterval?`, but the accuracy overload of `XCTAssertEqual` requires a non-optional `Double`, so the test target failed to compile.

- **Resolution:** Unwrapped the value with `try XCTUnwrap(...)` before the accuracy assertion and marked the test method `throws`.

### 3. Date precision lost in Codable round-trips
Two `TaskItem` round-trip tests failed even though the printed structs looked identical. The cause: those tests let `createdAt` default to `Date()` (sub-second precision), and ISO 8601 encoding truncates to whole seconds, so the decoded value differed by microseconds and failed `Equatable`.

- **Resolution:** Gave those tests explicit whole-second timestamps, matching the other round-trip tests. Worth remembering when Firestore serialization is added in Task 3.

### 4. SwiftLint config placement warning
SwiftLint warned that `unused_import` should live under `analyzer_rules`, not `opt_in_rules`.

- **Resolution:** Moved `unused_import` into an `analyzer_rules` section. Lint now runs with zero warnings.

## Notes for the next task

Task 2 (Firebase + authentication) requires manual console steps on your side: creating the Firebase project, registering the iOS bundle id, enabling Email/Password sign-in, and adding `GoogleService-Info.plist` to the project. The `AuthService` protocol is already defined and ready for a `FirebaseAuthService` implementation and a `MockAuthService` for tests.

## AI was used to clean up a lot fo the documentation and keep me organized on priority and next steps
