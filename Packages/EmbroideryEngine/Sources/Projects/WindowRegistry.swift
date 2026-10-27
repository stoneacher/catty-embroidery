import Foundation

/// Which project each window holds, and the name of the draft it holds, if any (brief D7).
/// Kept out of `ProjectLibrary` in slice 7, which had reached SwiftLint's length limit; the
/// library forwards to it and stays the only API.
///
/// `owner` is held weakly, only so a window torn down without unregistering stops counting.
struct WindowRegistry {
    private var entries: [WindowToken: Registration] = [:]

    /// Replaces whatever `window` held before — the draft name included, so a window
    /// re-registers with `nil` once its draft has a file. Dead entries are pruned here, which
    /// is also when observers hear of them.
    mutating func register(_ window: WindowToken, owner: AnyObject, holding id: ProjectID, draftName: String?) {
        pruneDead()
        entries[window] = Registration(owner: owner, projectID: id, draftName: draftName)
    }

    /// A late message about a project the window has since left does nothing, so it cannot
    /// remove its successor.
    mutating func unregister(_ window: WindowToken, from id: ProjectID) {
        guard entries[window]?.projectID == id else {
            return
        }
        entries[window] = nil
    }

    /// Whether any entry's window has gone without unregistering.
    var hasDeadEntries: Bool {
        entries.values.contains { $0.owner == nil }
    }

    mutating func pruneDead() {
        entries = entries.filter { $0.value.owner != nil }
    }

    /// The live windows holding `id`.
    func holders(of id: ProjectID) -> Set<WindowToken> {
        Set(entries.compactMap { window, registration in
            registration.owner != nil && registration.projectID == id ? window : nil
        })
    }

    /// The names of the drafts live windows hold.
    var draftNames: [String] {
        entries.values.filter { $0.owner != nil }.compactMap(\.draftName)
    }
}

private struct Registration {
    weak var owner: AnyObject?
    let projectID: ProjectID
    let draftName: String?
}
