import SwiftUI

/// A supporter's view of someone else's task list (6.7). The controls shown
/// follow the permission on the link, and update live if the owner changes it.
struct SupportedOwnerTasksView: View {
    @ObservedObject var viewModel: SupportLinksViewModel
    let linkId: String
    let taskRepository: TaskRepository

    var body: some View {
        if let link = viewModel.link(withId: linkId) {
            TaskListView(
                repository: taskRepository,
                ownerUid: link.ownerUid,
                currentUid: viewModel.user.id,
                access: .supporter(link.permission),
                title: link.ownerLabel
            )
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView {
                Label("Access removed", systemImage: "person.crop.circle.badge.xmark")
            } description: {
                Text("This person stopped sharing their tasks with you.")
            }
        }
    }
}
