import SwiftUI

/// Minimal "add task" form: title, notes, priority, and a time budget.
/// Fixed time slots arrive with the hybrid schedule form in Task 4.
struct AddTaskView: View {
    @ObservedObject var viewModel: TaskListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var notes = ""
    @State private var priority: Priority = .medium
    @State private var durationMinutes = 25
    @State private var isSaving = false

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
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

                Section("Time allotted") {
                    Stepper(value: $durationMinutes, in: 5...240, step: 5) {
                        Text("\(durationMinutes) minutes")
                    }
                }

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

    private func save() {
        isSaving = true
        Task {
            let succeeded = await viewModel.addTask(
                title: title,
                notes: notes,
                priority: priority,
                durationMinutes: durationMinutes
            )
            isSaving = false
            if succeeded { dismiss() }
        }
    }
}

#Preview {
    AddTaskView(
        viewModel: TaskListViewModel(repository: MockTaskRepository(), ownerUid: "me")
    )
}
