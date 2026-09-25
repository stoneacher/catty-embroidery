import ProgramModel

/// The editor's bounded, coalesced undo/redo history (ADR-006, ADR-036).
///
/// **The stack owns the working program.** It holds `current` plus the program
/// as it was *before* each recorded edit, and edits go through `apply(_:coalescing:)`,
/// which runs `EditorCore.apply` on `current` itself. So there is one copy of
/// the program, not two kept in step, and no result computed from a stale base
/// can be recorded. US-405's view model reads `current` rather than storing its
/// own.
///
/// **Snapshots, not inverse operations.** `Program` is a value type with COW at
/// every level and `Brick`/`Formula` are `indirect`, so a snapshot of an
/// unmutated program is a handful of retains, and one edit copies one `[Brick]`
/// buffer. The bound is structural — `capacity` entries — and deliberately not
/// a byte or timing budget (US-309's CI-refuted bound is the precedent).
///
/// **Coalescing is an explicit session, never a timer**, so this is a pure value
/// with no clock. `beginEdit(of:)` mints a key; an applied edit folds into the
/// top entry iff its key is the open session's *and* the top entry's. Anything
/// else — a `nil` key, a closed or superseded key, a top entry changed by undo,
/// redo or an un-keyed edit — pushes.
///
/// Never persisted (ADR-006).
public struct UndoStack: Equatable, Sendable {
    /// The most undo entries kept; pushing past it evicts the oldest.
    public static let capacity = 50

    /// The working program.
    public private(set) var current: Program

    /// The open coalescing session, if any.
    public private(set) var openSession: CoalescingKey?

    private var undoEntries: [Entry] = []
    private var redoPrograms: [Program] = []

    /// Keeps counting across `reset(to:)`, so no key minted after a reset can
    /// equal one from before it. That is why the view model must `reset` rather
    /// than re-create the stack on a whole-program replacement.
    private var nextSerial = 0

    public init(program: Program) {
        current = program
    }

    public var canUndo: Bool {
        !undoEntries.isEmpty
    }

    public var canRedo: Bool {
        !redoPrograms.isEmpty
    }

    public var undoDepth: Int {
        undoEntries.count
    }

    public var redoDepth: Int {
        redoPrograms.count
    }

    /// Apply `action` to `current`, recording it for undo.
    ///
    /// Records nothing when the action is rejected (the reason ADR-033 made
    /// `apply` return a result) or when it applied but changed nothing — a
    /// dead undo tap, and clearing redo for it would destroy history over an
    /// edit that did not happen.
    @discardableResult
    public mutating func apply(_ action: EditAction, coalescing key: CoalescingKey? = nil) -> EditResult {
        let result = EditorCore.apply(action, to: current)
        guard case let .applied(program) = result, program != current else { return result }

        let coalesces = key != nil && key == openSession && undoEntries.last?.key == key
        if !coalesces {
            push(Entry(before: current, key: key))
        }
        redoPrograms.removeAll()
        current = program
        return result
    }

    /// Step back one entry; `nil`, with nothing changed, when there is none.
    @discardableResult
    public mutating func undo() -> Program? {
        guard let entry = undoEntries.popLast() else { return nil }
        redoPrograms.append(current)
        current = entry.before
        return current
    }

    /// Step forward one entry; `nil`, with nothing changed, when there is none.
    ///
    /// The re-pushed entry is **sealed** (no key): folding a later keystroke into
    /// it would silently change what this redo restored.
    @discardableResult
    public mutating func redo() -> Program? {
        guard let program = redoPrograms.popLast() else { return nil }
        push(Entry(before: current, key: nil))
        current = program
        return current
    }

    /// Open a coalescing session for the brick at `address`, superseding any
    /// session already open.
    public mutating func beginEdit(of address: BrickAddress) -> CoalescingKey {
        let key = CoalescingKey(address: address, serial: nextSerial)
        nextSerial += 1
        openSession = key
        return key
    }

    /// Close the session `key` names — and only that one. Idempotent, and a
    /// no-op for a key that is not the open session's: a late call from a
    /// superseded sheet must not close its successor's session.
    public mutating func endEdit(_ key: CoalescingKey) {
        if openSession == key {
            openSession = nil
        }
    }

    /// Close whatever session is open, for teardown paths that hold no key
    /// (ADR-023's container swap can dismiss a sheet without its `endEdit`).
    public mutating func abandonEdit() {
        openSession = nil
    }

    /// Replace the program wholesale — pick a sample, load from disk, new
    /// program — clearing both directions and any open session.
    public mutating func reset(to program: Program) {
        current = program
        undoEntries.removeAll()
        redoPrograms.removeAll()
        openSession = nil
    }

    private mutating func push(_ entry: Entry) {
        undoEntries.append(entry)
        if undoEntries.count > Self.capacity {
            undoEntries.removeFirst(undoEntries.count - Self.capacity)
        }
    }

    /// The program as it was before an edit, and the session it was recorded
    /// under (`nil` for an un-keyed or sealed entry).
    private struct Entry: Equatable, Sendable {
        let before: Program
        let key: CoalescingKey?
    }
}
