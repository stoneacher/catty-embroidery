import Foundation

/// The editor's `UndoManager`, kept in **full agreement** with the package `UndoStack` (US-411,
/// ADR-036's 2026-10-09 amendment): after every history transition it offers exactly the
/// stack's undo and redo depths, so shake, ⌘Z and the edit menu reach the same history the
/// toolbar does.
///
/// **The stack stays the truth; the manager is a trigger surface.** Its entries are stateless
/// proxies — "step the editor back", "step it forward" — so agreement means matching *depths*,
/// and the snapshots never leave `UndoStack`.
///
/// **The manager is the app's own, and never groups by event.** `@Environment(\.undoManager)`
/// is the window's shared manager (probe E1), which text fields use too and which merges every
/// registration in one run-loop turn into one step (P7, P8). An owned manager with
/// `groupsByEvent == false` is what lets `sync` rebuild an exact state, and keeps a keystroke's
/// text undo out of the program's history. `UndoResponderAnchor` vends it to the responder chain.
///
/// How the two directions are rebuilt, both executed before this was written (ADR-032
/// invariant 4):
/// - **From outside a handler, `sync` pumps**: it registers `undo + redo` proxies, one group
///   each, then silently undoes `redo` of them. A registration made while the manager is undoing
///   lands on its redo side (P1), and that is the only way to put one there (P4).
/// - **A system-driven undo or redo keeps agreement by itself.** Its proxy steps the editor and
///   registers the inverse proxy, which the manager files on the opposite side (P1, P3). `sync`
///   must not run then: calling `undo()` from inside a handler throws (P6).
@MainActor
final class UndoManagerBridge {
    let manager: UndoManager

    private let undo: () -> Bool
    private let redo: () -> Bool
    private let depths: () -> (undo: Int, redo: Int)

    /// While `sync` builds the redo side, the proxies it undoes only re-register.
    private var isPumping = false

    /// While a system-driven proxy runs, the stack's change must not trigger a rebuild (P6).
    private var isHandlingSystemAction = false

    /// `undo` and `redo` step the editor and report whether there was a step; `depths` reads the
    /// stack. Closures rather than the view model itself, so the bridge cannot reach anything else.
    init(
        manager: UndoManager,
        undo: @escaping () -> Bool,
        redo: @escaping () -> Bool,
        depths: @escaping () -> (undo: Int, redo: Int)
    ) {
        manager.groupsByEvent = false
        self.manager = manager
        self.undo = undo
        self.redo = redo
        self.depths = depths
    }

    /// Rebuilds the manager to the stack's depths. A no-op while a system-driven step is running,
    /// which leaves agreement to that step's inverse registration.
    func sync() {
        guard !isHandlingSystemAction else { return }
        let (undoDepth, redoDepth) = depths()
        manager.removeAllActions()
        isPumping = true
        defer { isPumping = false }
        for _ in 0 ..< undoDepth + redoDepth {
            manager.beginUndoGrouping()
            register(.undo)
            manager.endUndoGrouping()
        }
        for _ in 0 ..< redoDepth {
            manager.undo()
        }
    }

    /// Files a proxy that, when the manager invokes it, performs `direction`.
    private func register(_ direction: HistoryDirection) {
        manager.registerUndo(withTarget: self) { bridge in
            bridge.perform(direction)
        }
    }

    private func perform(_ direction: HistoryDirection) {
        let inverse: HistoryDirection = direction == .undo ? .redo : .undo
        guard !isPumping else {
            register(inverse)
            return
        }
        isHandlingSystemAction = true
        let stepped = direction == .undo ? undo() : redo()
        isHandlingSystemAction = false
        register(inverse)
        if !stepped {
            // The manager offered a step the stack did not have — agreement was already lost.
            // Rebuild once the handler has returned; rebuilding here would throw (P6).
            Task { @MainActor [weak self] in self?.sync() }
        }
    }
}

extension UndoManager {
    /// The editor's own history manager: one step per registration group, never per event.
    static func makeEditorHistory() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }
}
