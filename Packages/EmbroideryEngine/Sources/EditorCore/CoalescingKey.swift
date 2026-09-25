import ProgramModel

/// The identity of one coalescing session on an `UndoStack` (ADR-036).
///
/// Minted **only** by `UndoStack.beginEdit(of:)` — the initializer is internal
/// — so a caller cannot forge a key that collides with a session it did not
/// open. The `serial` is what makes two sessions on the same brick distinct: a
/// key from a closed or superseded session never equals the open one, which is
/// what stops a torn-down parameter sheet (ADR-023's container swap) from
/// swallowing the next session's undo entry.
public struct CoalescingKey: Hashable, Sendable {
    /// The brick the session edits. Informational — coalescing compares whole
    /// keys, and the serial alone already makes them unique per stack.
    public let address: BrickAddress

    let serial: Int
}
