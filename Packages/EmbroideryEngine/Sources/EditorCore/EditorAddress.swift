/// Where a script lives in a program: `Program → Scene → Object → Script`.
///
/// Index-based, with no identity in the model (ADR-034) — a `UUID` on each
/// brick would break whole-`Program` equality and `decode(resource) ==
/// builder()`, since two structurally identical programs would compare unequal.
/// The indices mirror `Script.movingPair(at:to:)`' existing convention.
///
/// Every component defaults to zero because M4's working program is
/// realistically one scene / one object / one script — both shipped samples are
/// — so ordinary call sites read `BrickAddress(brickIndex: 3)`. The type still
/// names all three, because the model permits more and an address that cannot
/// express that would be a lie.
public struct ScriptAddress: Sendable, Hashable {
    public var sceneIndex: Int
    public var objectIndex: Int
    public var scriptIndex: Int

    public init(sceneIndex: Int = 0, objectIndex: Int = 0, scriptIndex: Int = 0) {
        self.sceneIndex = sceneIndex
        self.objectIndex = objectIndex
        self.scriptIndex = scriptIndex
    }
}

/// A brick's position: its script's address plus an index into that script's
/// flat brick list (ADR-008).
///
/// Nested rather than a flat four-integer struct, because `ScriptAddress` is a
/// real address on its own — US-402's `.insert` and US-408's reorder address a
/// *script* plus an index — and nesting keeps a meaningless `brickIndex` out of
/// the script-level vocabulary.
///
/// The fields are `var` so US-408's index arithmetic can produce a shifted copy
/// without re-spelling every component. Resolution (`brick(at:)`) is **not**
/// here: nothing addresses a brick until US-402, which is also where an
/// out-of-bounds address acquires its policy — a rejection, not an optional
/// (ADR-033) — and writing the resolver now would mean writing it without its
/// failure semantics.
public struct BrickAddress: Sendable, Hashable {
    public var script: ScriptAddress
    public var brickIndex: Int

    public init(brickIndex: Int, script: ScriptAddress = ScriptAddress()) {
        self.brickIndex = brickIndex
        self.script = script
    }
}
