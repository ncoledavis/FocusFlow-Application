import SwiftUI

/// "Add task" form with the hybrid schedule: either a time budget (the clock
/// starts when the task becomes current) or a fixed time slot.
struct AddTaskView: View {
    @ObservedObject var viewModel: TaskListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var notes = ""
    @State private var priority: Priority = .medium
    @State private var scheduleType: ScheduleType = .duration
    @State private var durationMinutes = 25
    @State private var slotStart = AddTaskView.defaultSlotStart()
    @State private var slotFinish = AddTaskView.defaultSlotStart().addingTimeInterval(30 * 60)
    @State private var isSaving = false

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    private var schedule: TaskListViewModel.NewTaskSchedule {
        switch scheduleType {
        case .duration: return .duration(minutes: durationMinutes)
        case .fixed: return .fixed(start: slotStart, finish: slotFinish)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What do you need to do?", text: $title)
                        .submitLabel(.next)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases) { priority in
                            Text(priority.title).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                scheduleSection

                if let message = viewModel.errorMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.clearError()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        Section {
            Picker("Schedule", selection: $scheduleType) {
                Text("Time budget").tag(ScheduleType.duration)
                Text("Fixed time").tag(ScheduleType.fixed)
            }
            .pickerStyle(.segmented)

            switch scheduleType {
            case .duration:
                Stepper(value: $durationMinutes, in: 5...240, step: 5) {
                    Text("\(durationMinutes) minutes")
                }
            case .fixed:
                DatePicker("Starts", selection: $slotStart)
                DatePicker("Finishes", selection: $slotFinish, in: slotStart...)
            }
        } header: {
            Text("Time")
        } footer: {
            Text(scheduleType == .duration
                 ? "The countdown starts when this becomes your current task."
                 : "The countdown runs toward the finish time.")
        }
        .onChange(of: slotStart) { _, newStart in
            // Keep the finish after the start when the start moves later.
            if slotFinish <= newStart {
                slotFinish = newStart.addingTimeInterval(30 * 60)
            }
        }
    }

    // MARK: - Actions

    private func save() {
        isSaving = true
        Task {
            let succeeded = await viewModel.addTask(
                title: title,
                notes: notes,
                priority: priority,
                schedule: schedule
            )
            isSaving = false
            if succeeded { dismiss() }
        }
    }

    /// The next quarter hour, a sensible default for a fixed slot.
    private static func defaultSlotStart() -> Date {
        let quarterHour: TimeInterval = 15 * 60
        let now = Date().timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (now / quarterHour).rounded(.up) * quarterHour)
    }
}

#Preview {
    AddTaskView(
        viewModel: TaskListViewModel(repository: MockTaskRepository(), ownerUid: "me")
    )
}
