import ProgramModel

/// What a list gesture or an accessibility action means as an `EditAction` (US-408).
///
/// Pure arithmetic over a script, here rather than in a view for the reason ADR-008 put the
/// move itself in the model: a reorder that lands one index wrong produces a brick inside a
/// loop the user never put it in, and the conversion is the named off-by-one of ADR-035.
///
/// Every function **builds** an action and never applies one. `EditorCore.apply` stays the
/// only authority on what is refused (ADR-033), so a source these functions do not screen —
/// a `loopEnd` handed to `moveAction(fromOffsets:toOffset:in:)` — is still turned into a
/// `.move` and rejected there, with its reason, rather than refused twice in two vocabularies.
/// `nil` means "there is no edit to make", not "this edit is refused".
///
/// The offsets are `some Collection<Int>` rather than `IndexSet` so that `EditorCore` stays
/// free of Foundation; `IndexSet` conforms, and a test can pass an array literal.
public extension Script {
    /// The `.move` a SwiftUI `.onMove(fromOffsets:toOffset:)` callback means, or `nil` when
    /// there is none to make.
    func moveAction(
        fromOffsets source: some Collection<Int>,
        toOffset: Int,
        in script: ScriptAddress
    ) -> EditAction? {
        // Stub (US-408 red phase): the naive pass-through, which is the bug itself.
        source.first.map { .move(from: BrickAddress(brickIndex: $0, script: script), to: toOffset) }
    }

    /// The `.delete` a SwiftUI `.onDelete(perform:)` callback means, or `nil`.
    func deleteAction(atOffsets _: some Collection<Int>, in _: ScriptAddress) -> EditAction? {
        nil // Stub (US-408 red phase).
    }

    /// VoiceOver's "Move Up": the block at `index` jumps over its previous sibling block.
    func moveUpAction(ofBrickAt _: Int, in _: ScriptAddress) -> EditAction? {
        nil // Stub (US-408 red phase).
    }

    /// VoiceOver's "Move Down": the block at `index` jumps over its next sibling block.
    func moveDownAction(ofBrickAt _: Int, in _: ScriptAddress) -> EditAction? {
        nil // Stub (US-408 red phase).
    }

    /// VoiceOver's "Move Above Loop": the first block of a loop body leaves it upward.
    func moveAboveLoopAction(ofBrickAt _: Int, in _: ScriptAddress) -> EditAction? {
        nil // Stub (US-408 red phase).
    }

    /// VoiceOver's "Move Below Loop": the last block of a loop body leaves it downward.
    func moveBelowLoopAction(ofBrickAt _: Int, in _: ScriptAddress) -> EditAction? {
        nil // Stub (US-408 red phase).
    }
}
