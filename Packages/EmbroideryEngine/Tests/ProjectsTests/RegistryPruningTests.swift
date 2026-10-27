import Foundation
import Observation
@testable import Projects
import Testing

/// A window torn down without unregistering stops counting at once (`holders(of:)` skips dead
/// owners), but until slice 8 nothing *told* the other windows: the entry was pruned only at
/// the next registration, so a row could keep saying "open in another window" (PR #78
/// deferral, Codex Low). `pruneDeadRegistrations()` is the explicit transition the app calls
/// when a scene disconnects or becomes active (brief D7).
@MainActor
@Suite("Registry pruning")
struct RegistryPruningTests {
    static let project = ProjectID.fixed(1)

    /// Whether `change` notifies an observer of what `read` reads.
    private static func notifies(_ read: @escaping () -> Void, when change: () -> Void) -> Bool {
        let fired = PruningFlag()
        withObservationTracking(read, onChange: { fired.value = true })
        change()
        return fired.value
    }

    /// The owner is released when this returns, as a scene's model is when the scene goes
    /// without `onDisappear`.
    private static func registerAWindowThatDies(in library: ProjectLibrary) {
        let owner = WindowOwner()
        library.register(WindowToken(), owner: owner, holding: project, draftName: nil)
    }

    @Test("pruning a window that died without unregistering tells the observers of who holds the project")
    func pruningADeadWindowNotifies() {
        let library = ProjectLibrary.inMemory()
        Self.registerAWindowThatDies(in: library)
        #expect(library.holders(of: Self.project).isEmpty, "the premise: a dead owner already counts for nothing")

        #expect(Self.notifies {
            _ = library.holders(of: Self.project)
        } when: {
            library.pruneDeadRegistrations()
        })
    }

    @Test("pruning with every window alive changes nothing, so no one is notified")
    func pruningLiveWindowsIsQuiet() {
        let library = ProjectLibrary.inMemory()
        let owner = WindowOwner()
        let window = WindowToken()
        library.register(window, owner: owner, holding: Self.project, draftName: nil)

        #expect(!Self.notifies {
            _ = library.holders(of: Self.project)
        } when: {
            library.pruneDeadRegistrations()
        })
        #expect(library.holders(of: Self.project) == [window])
    }
}

/// A flag an observation callback can set; the callback is `@Sendable`, so it cannot capture a
/// local `var`.
private final class PruningFlag: @unchecked Sendable {
    var value = false
}
