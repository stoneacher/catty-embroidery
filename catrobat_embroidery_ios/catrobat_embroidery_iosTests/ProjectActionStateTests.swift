@testable import catrobat_embroidery_ios
import Foundation
import Projects
import Testing

/// Which of a row's actions are allowed now, and why not (project management slice 8; brief
/// D7): renaming or deleting a project another window holds is disabled with a reason, while
/// opening and duplicating it stay allowed.
@MainActor
@Suite("Project action states")
struct ProjectActionStateTests {
    static func row(badge: ProjectBadge? = nil) -> ProjectRow {
        ProjectRow(id: .fixed(1), name: "Flower", modified: .now, badge: badge, isSelected: false)
    }

    @Test("a project no other window holds allows every action")
    func everythingAllowed() {
        let states = ProjectActions.states(for: Self.row(), heldElsewhere: false)

        #expect(states.map(\.action) == [.open, .rename, .duplicate, .delete])
        #expect(states.allSatisfy { $0.isEnabled })
    }

    @Test("a project another window holds cannot be renamed or deleted, and says why")
    func heldElsewhere() {
        let states = ProjectActions.states(for: Self.row(), heldElsewhere: true)

        #expect(states.map(\.action) == [.open, .rename, .duplicate, .delete])
        #expect(states.filter(\.isEnabled).map(\.action) == [.open, .duplicate])
        #expect(states.filter { !$0.isEnabled }.allSatisfy { $0.blocked == .openInAnotherWindow })
    }

    @Test("a refused row offers only delete")
    func refusedRow() {
        let states = ProjectActions.states(for: Self.row(badge: .damaged), heldElsewhere: false)

        #expect(states == [ProjectActionState(action: .delete, blocked: nil)])
    }

    @Test("the reason is a sentence, not its key")
    func reasonText() {
        let reason = String(localized: ProjectActionBlock.openInAnotherWindow.reason)

        #expect(!reason.isEmpty)
        #expect(!reason.hasPrefix("project."))
    }
}
