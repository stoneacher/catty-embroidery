import SwiftUI

/// A project row's context menu and swipe action (project management slice 8; brief D7, D9).
///
/// It lays out `ProjectActions.states(for:heldElsewhere:)` and decides nothing: which actions
/// a row has (a refused row: Delete only, D11) and which are disabled with what reason (D7)
/// come from there, where they are tested. `.open` is not here because it is the row's tap.
///
/// Delete only *asks* (`AppModel.requestDeletion(of:)`); the one confirmation dialog lives on
/// `ProjectListView`, so nothing is removed from a menu or a swipe alone (D9).
struct ProjectRowActions: ViewModifier {
    let states: [ProjectActionState]
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if let rename = state(of: .rename) {
                    // Slice 9: the rename sheet. Until then the item is shown with its D7 state,
                    // so the menu's shape and its disabled reason are already what ships.
                    button(rename, title: .projectActionRename, systemImage: "pencil") {}
                }
                if let duplicate = state(of: .duplicate) {
                    button(duplicate, title: .projectActionDuplicate, systemImage: "plus.square.on.square",
                           action: onDuplicate)
                }
                if state(of: .rename) != nil || state(of: .duplicate) != nil {
                    Divider()
                }
                if let delete = state(of: .delete) {
                    button(delete, title: .projectActionDelete, systemImage: "trash", role: .destructive,
                           action: onDelete)
                }
            }
            // Delete only, and only when it is allowed: a swipe button has no disabled look,
            // so a blocked Delete would be a red button that does nothing. Not a full swipe,
            // so the gesture alone never reaches the dialog by accident.
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let delete = state(of: .delete), delete.isEnabled {
                    Button(role: .destructive, action: onDelete) {
                        Label {
                            Text(.projectActionDelete)
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
    }

    private func state(of action: ProjectRowAction) -> ProjectActionState? {
        states.first { $0.action == action }
    }

    /// A disabled item keeps its place and shows why as the menu item's subtitle (the second
    /// `Text`), rather than vanishing: an action that is simply missing reads as "this app
    /// cannot do that" instead of "not while the design is open elsewhere" (D7).
    private func button(
        _ state: ProjectActionState,
        title: LocalizedStringResource,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label {
                Text(title)
                if let reason = state.blocked?.reason {
                    Text(reason)
                }
            } icon: {
                Image(systemName: systemImage)
            }
        }
        .disabled(!state.isEnabled)
    }
}

extension View {
    func projectRowActions(
        _ states: [ProjectActionState],
        onDuplicate: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        modifier(ProjectRowActions(states: states, onDuplicate: onDuplicate, onDelete: onDelete))
    }
}
