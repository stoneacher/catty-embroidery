import ProgramModel

/// The identity of one coalescing session on an `UndoStack` (ADR-036).
///
/// Minted **only** by `UndoStack.beginEdit(of:)` — the memberwise initializer
/// is internal — so a caller outside `EditorCore` cannot construct one. The
/// `serial` is what makes two sessions on the same brick distinct: a key from a
/// closed or superseded session never equals the open one, which is what stops
/// a torn-down parameter sheet (ADR-023's container swap) from swallowing the
/// next session's undo entry.
///
/// **Unique within one stack's history, not globally.** `UndoStack` is a value
/// type: a copy mints the same serials as the original, and two fresh stacks
/// both start at zero, so a key from a *different* stack can match. The editor
/// holds exactly one stack, which is why this is a documented limit rather than
/// a check.
public struct CoalescingKey: Hashable, Sendable {
    /// The brick the session edits. Informational — coalescing compares whole
    /// keys, and the serial alone already makes them unique per stack.
    public let address: BrickAddress

    let serial: Int
}
