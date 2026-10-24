# FocusFlow — Project Plan

An iOS application that helps people with ADHD work on a schedule using a calendar and a task time model. It has a login system, a one-task-at-a-time to-do list, supporter accounts that can help manage tasks with role-based permissions, and calendar integration (Apple + Google).

## Problem Statement
People with ADHD struggle with task prioritization, time awareness, and following through on schedules. This iOS app reduces overwhelm by showing one task at a time, giving each task a clear time allotment and target finish time, letting a trusted supporter help manage the task list, and surfacing calendar context alongside tasks. Scope for this phase is a working, demoable prototype.

## Requirements
- Working iOS prototype (SwiftUI + MVVM, iOS 17+) demoable on simulator/device
- Firebase Authentication for login; Firestore for real-time data and two-user sync
- One-at-a-time to-do UX: show the top-priority task, user can skip/reorder; priority is a strong suggestion
- Task time model: each task has an allotted duration and a target finish time; UI shows time given and a countdown toward finish (not a user-run stopwatch)
- When time runs out and the task isn't done: prompt "Still working on this? Add more time / Mark done / Skip"
- Task scheduling is hybrid: each task can have either a duration or a fixed time slot
- Supporter linking with role-based permissions (view / add / edit), controlled by the ADHD user
- Calendar: read-only for now, designed for future two-way sync; full protocol-based integration layer with real EventKit adapter, real Google adapter, and a mock adapter used for the demo

## Background / Research Findings
- Firebase on iOS installs cleanly via Swift Package Manager (firebase-ios-sdk), pulling only FirebaseAuth and FirebaseFirestore. Firestore gives real-time listeners, ideal for a supporter and ADHD user seeing live updates to the same task list.
- EventKit (iOS 17+) uses requestFullAccessToEvents / requestWriteOnlyAccessToEvents and requires NSCalendarsFullAccessUsageDescription in Info.plist. Read-only now maps to full-access read; the layer is built so write operations can be added later.
- Google Calendar requires GoogleSignIn for OAuth plus the Calendar REST API (calendar.readonly scope). This is heavier to set up (OAuth client, consent screen), which is why a protocol-based layer with a mock adapter lets us build and demo the whole app without blocking on OAuth config.
- MVVM + protocol-oriented services keeps SwiftUI views thin, makes the calendar providers swappable, and makes view models testable with mock repositories.

## Architecture
Layered SwiftUI app:
- Views (SwiftUI): Auth, TaskFocus, TaskList, Supporters, Calendar, Settings
- ViewModels (MVVM, @Observable)
- Services / Repositories (protocols): AuthService, TaskRepository, LinkRepository, CalendarProvider
- Adapters: Firebase (Auth, Firestore); Calendar: EventKit, Google, Mock

### Data model (Firestore)
- users/{uid}: profile, role flags
- links/{linkId}: { ownerUid, supporterUid, permission: view|add|edit, status: pending|active }
- tasks/{taskId}: { ownerUid, title, notes, priority, scheduleType: duration|fixed, durationMinutes, startAt, targetFinishAt, status: pending|current|done|skipped, createdBy, order }

Permission enforcement happens in the app and in Firestore Security Rules (view = read only; add = create; edit = modify priority/order).

Task selection: current task = highest priority among pending, with manual skip/reorder. Overdue handling via local notifications + an in-app prompt sheet.

Login: email/password in Task 2, with Google Sign-In added in Task 7 for calendar access.

## Task Breakdown

### Task 1: Project scaffold and architecture skeleton
- [x] 1.1 Create a new Xcode project: SwiftUI app, iOS 17+ deployment target, name it FocusFlow.
- [x] 1.2 Create top-level folders/groups: Views, ViewModels, Models, Services, Adapters, Resources, Tests.
- [x] 1.3 Add SwiftLint (via SPM plugin or build phase) with a basic .swiftlint.yml.
- [x] 1.4 Define enums: Priority (low/medium/high/urgent), TaskStatus (pending/current/done/skipped), ScheduleType (duration/fixed), LinkPermission (view/add/edit), LinkStatus (pending/active).
- [x] 1.5 Define model structs: AppUser, TaskItem, SupporterLink with Codable conformance.
- [x] 1.6 Add computed properties to TaskItem (targetFinishAt from startAt + duration, timeRemaining).
- [x] 1.7 Define empty protocols: AuthService, TaskRepository, LinkRepository, CalendarProvider.
- [x] 1.8 Add a placeholder root view so the app launches.
- [x] 1.9 Write unit tests for model Codable round-trips and TaskItem computed properties.
- Demo: app builds and launches to a placeholder screen; model tests pass.

### Task 2: Firebase integration and authentication
- [ ] 2.1 Create the Firebase project in the console; register the iOS bundle ID. _(manual — Firebase console; bundle id is `com.focusflow.app`)_
- [x] 2.2 Add the Firebase SDK via SPM; include only FirebaseAuth and FirebaseFirestore.
- [~] 2.3 Add GoogleService-Info.plist to the project; configure Firebase in the app entry point. _(code done via FirebaseConfig; drop in the plist from the console to activate)_
- [ ] 2.4 Enable Email/Password sign-in in the Firebase Auth console. _(manual — Firebase console)_
- [x] 2.5 Define the AuthService protocol methods: signUp, signIn, signOut, currentUser publisher.
- [x] 2.6 Implement FirebaseAuthService conforming to AuthService.
- [x] 2.7 Build AuthViewModel with form state, validation, and error handling.
- [x] 2.8 Build the Login view (email, password, sign-in button, error display).
- [x] 2.9 Build the Sign-Up view and navigation between login/sign-up.
- [x] 2.10 Build the root router view that shows auth vs. main app based on session state.
- [x] 2.11 Create MockAuthService and write AuthViewModel tests (success, bad credentials, sign-out).
- Demo: create an account, log in, see a home screen, log out; session persists across relaunch.
- Note: items 2.1, 2.3 (plist), and 2.4 require Firebase console access. Until the plist is added, the app runs against MockAuthService so the full flow is still demoable.

### Task 3: Task data layer with Firestore
- [ ] 3.1 Design the Firestore tasks collection shape and document the fields.
- [ ] 3.2 Define TaskRepository protocol: create, update, delete, observeTasks(forOwner:).
- [ ] 3.3 Implement FirestoreTaskRepository create/update/delete.
- [ ] 3.4 Add the real-time listener in observeTasks and map snapshots to TaskItem.
- [ ] 3.5 Build TaskListViewModel that subscribes to the repository and exposes sorted tasks.
- [ ] 3.6 Build a basic task list view (list rows + an "Add task" button with a minimal form).
- [ ] 3.7 Create MockTaskRepository; write TaskListViewModel tests for add/update/delete and priority ordering.
- Demo: logged-in user adds tasks and sees them appear instantly in a live list.

### Task 4: One-at-a-time focus view with time model
- [ ] 4.1 Add current-task selection logic (highest-priority pending) to a FocusViewModel.
- [ ] 4.2 Build the focus screen layout: single task card with title, notes, allotted duration.
- [ ] 4.3 Add a clock-style countdown display toward targetFinishAt, updating every second.
- [ ] 4.4 Extend the task-creation form to support the hybrid schedule (duration OR fixed time slot).
- [ ] 4.5 Implement the "Done" action (mark done, advance to next).
- [ ] 4.6 Implement the "Skip" action (mark skipped, advance to next).
- [ ] 4.7 Write unit tests for current-task selection, time-remaining math, and advance logic.
- Demo: user sees one task with its time budget and live countdown; done/skip advances to the next.

### Task 5: Overdue handling and notifications
- [ ] 5.1 Add a NotificationService wrapper around UNUserNotificationCenter; request permission with fallback.
- [ ] 5.2 Schedule a local notification at the current task's targetFinishAt; cancel it on done/skip.
- [ ] 5.3 Detect in-app expiry when the countdown reaches zero and set an "overdue" state.
- [ ] 5.4 Build the prompt sheet: "Add more time / Mark done / Skip".
- [ ] 5.5 Implement "Add more time" to extend targetFinishAt and reschedule the notification.
- [ ] 5.6 Write unit tests for the overdue transition and the add-more-time extension.
- Demo: let a short task expire and see the prompt + notification; adding time resets the countdown.

### Task 6: Supporter linking and role-based permissions
- [ ] 6.1 Design the Firestore links collection and document the fields.
- [ ] 6.2 Define LinkRepository protocol: createInvite, acceptInvite, updatePermission, revoke, observeLinks.
- [ ] 6.3 Implement invite generation (code or email) in FirestoreLinkRepository.
- [ ] 6.4 Implement accept-invite flow that creates an active link.
- [ ] 6.5 Build the owner's Supporters management UI (list, change permission, revoke).
- [ ] 6.6 Build the invite-entry UI on the supporter side.
- [ ] 6.7 Build the supporter-side view of the owner's task list, gated by permission.
- [ ] 6.8 Enforce permissions in view models (view can't add; add can create; edit can modify priority/order).
- [ ] 6.9 Write Firestore Security Rules matching each permission level.
- [ ] 6.10 Write view model tests for invite/accept/revoke and permission gating.
- Demo: a second account accepts an invite and, per role, adds tasks or edits priority live.

### Task 7: Calendar integration layer (mock + real adapters)
- [ ] 7.1 Define the CalendarProvider protocol: requestAccess, fetchEvents(in:), and a shared CalendarEvent model.
- [ ] 7.2 Implement MockCalendarProvider with sample events for the demo.
- [ ] 7.3 Build a CalendarService that aggregates providers behind one interface with a selectable active provider.
- [ ] 7.4 Add Info.plist NSCalendarsFullAccessUsageDescription.
- [ ] 7.5 Implement EventKitCalendarProvider (iOS 17 full-access read, map EKEvent to CalendarEvent).
- [ ] 7.6 Set up the Google OAuth client + consent screen; add GoogleSignIn via SPM.
- [ ] 7.7 Implement GoogleCalendarProvider (sign-in + Calendar readonly API, map to CalendarEvent).
- [ ] 7.8 Build a basic calendar screen that lists events from the active (mock) provider.
- [ ] 7.9 Write CalendarService tests against the mock for merge/sort; structure adapters for integration testing.
- Demo: calendar screen shows mock events; flipping the provider flag pulls real Apple events on a device.

### Task 8: Calendar-aware task view and polish
- [ ] 8.1 Build a day/timeline view model that merges calendar events with fixed-time tasks into one sorted list.
- [ ] 8.2 Build the timeline UI showing events and scheduled tasks together.
- [ ] 8.3 Apply ADHD-friendly styling: clear hierarchy, large tap targets, low-distraction palette.
- [ ] 8.4 Add empty states for each screen (no tasks, no events, no supporters).
- [ ] 8.5 Add loading and error states across screens.
- [ ] 8.6 Write view model tests for the merged timeline sorting.
- Demo: user sees a unified day view of tasks and calendar events; app feels cohesive.

### Task 9: End-to-end wiring, settings, and hardening
- [ ] 9.1 Build the Settings screen shell with navigation.
- [ ] 9.2 Add profile display/edit and a notifications toggle.
- [ ] 9.3 Add calendar provider selection in settings.
- [ ] 9.4 Add sign-out and delete-account actions.
- [ ] 9.5 Verify the full two-account flow end to end (owner + supporter).
- [ ] 9.6 Confirm Firestore Security Rules are enforced for each permission level.
- [ ] 9.7 Handle remaining offline/empty/error edge cases.
- [ ] 9.8 Add the app icon and launch screen.
- [ ] 9.9 Run the full test suite and fix any failures.
- Demo: complete walkthrough — sign up, link a supporter, supporter adds a prioritized task, user focuses with a live countdown, task expires and is extended, calendar context displays — all working together.
