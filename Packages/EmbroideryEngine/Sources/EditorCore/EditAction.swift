import ProgramModel

/// Every way the editor can change a program — ADR-006 pattern 1 made concrete.
///
/// Six cases, and that is the whole vocabulary: palette add, drag reorder,
/// swipe delete, parameter change, rename and — since US-410 — declaring a
/// variable are each one of them. Views never
/// mutate the program tree; they build one of these and hand it to
/// `EditorCore.apply(_:to:)`, which is the single place undo (US-403), autosave
/// (US-406) and run-invalidation (ADR-038) hook into.
///
/// **Addressing is index-based** (ADR-034): `Brick` carries no identity, and a
/// `UUID` field would break whole-`Program` equality and the
/// `decode(resource) == builder()` guarantee the samples rest on.
public enum EditAction: Equatable, Sendable {
    /// Insert a kind's template (`BrickKind.template()`) at an **insertion
    /// index** — `0 ... bricks.count`, so `count` appends and an empty script
    /// accepts `0`.
    ///
    /// A loop opener inserts **two** bricks, opener and `.loopEnd` (ADR-035), so
    /// a balanced script stays balanced by construction. `.loopEnd` on its own is
    /// rejected: it is the only way an action could mint an unbalanced script.
    ///
    /// The address is a plain insertion point. ADR-035's "tap-to-add with a loop
    /// opener selected inserts *inside* the loop" is a rule about **where the
    /// caller points**, and it belongs to US-409's call site — applying it here
    /// too would double-apply it.
    case insert(BrickKind, at: BrickAddress)

    /// Delete the block at a **position** — `0 ..< bricks.count`.
    ///
    /// At a loop opener this removes `range(ofPairAt:)` inclusive: opener, body
    /// and `loopEnd` (ADR-035, Catroid `BrickController.delete` parity). At a
    /// `loopEnd` it redirects to that end's own opener and does exactly the same
    /// thing, because a user swiping the "end of loop" row means "delete this
    /// loop".
    case delete(at: BrickAddress)

    /// Move the block at a position to `to`, an insertion index into the list
    /// **with the block already removed** — `0 ... (bricks.count − span)`, where
    /// `span` is 1 for a leaf and the pair's length for a loop opener.
    ///
    /// The post-removal convention is `Script.movingPair(at:to:)`'s, and it
    /// applies to **every** source kind so that `.move` means one thing
    /// regardless of the brick at `from`. SwiftUI's `.onMove` `toOffset` is a
    /// *pre*-removal index and differs for every downward move; converting
    /// between them is US-408's named deliverable (ADR-035).
    ///
    /// Moving a `loopEnd` is rejected — it is the one move that can split a pair.
    case move(from: BrickAddress, to: Int)

    /// Replace one brick, guarded to the **same `BrickKind`** (ADR-035). That
    /// guard is what makes this a *parameter* edit: it cannot turn a
    /// `repeatLoop` into a `sewUp` and orphan a `loopEnd`, so the pair invariant
    /// survives without re-validating anything.
    case replaceBrick(at: BrickAddress, with: Brick)

    /// Rename the program. Accepts any `String`, including the empty one:
    /// ADR-026's `DesignName` is an **export-boundary** type and the editor does
    /// not borrow it, so a program may carry a name that could not be written
    /// into a DST header and the export gate refuses it there instead.
    case renameProgram(String)

    /// Declare a zero-valued variable in the object that owns `script`
    /// (US-410, ADR-035 amendment) — the only way a variable comes into
    /// existence in the editor, and so what makes the variable menu reachable
    /// from the blank program at all.
    ///
    /// Refused for a name that breaks a `VariableName` rule, or one the object
    /// can already resolve in its own scope or the project's. It touches no
    /// script, so balance holds by construction. M4 has no rename or delete of
    /// a declaration; an unused one persists.
    ///
    /// The parameter editor applies it together with the `replaceBrick` that
    /// uses the name, under one coalescing key, so the pair is one undo entry
    /// and undo can never leave a brick naming an undeclared variable it had
    /// just declared.
    case declareVariable(name: String, script: ScriptAddress)
}
