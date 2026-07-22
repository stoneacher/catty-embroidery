import ProgramModel

/// A script compiled to a linear instruction array (ADR-008: the *model* stays
/// the flat paired brick list — compilation is interpreter-internal). Straight-
/// line bricks become one `.brick` each; the loop-control cases (added with the
/// loop story-commit) carry jump offsets, mirroring Catty `CBBackend`'s
/// flatten-to-instructions precedent.
enum Instruction: Sendable {
    /// A brick that produces a Catroid action — motion / data / wait / embroidery.
    /// Executing one such instruction costs exactly one tick (ADR-018).
    case brick(Brick)
}

/// Compiles a `Script` once into its linear instruction array. Straight-line for
/// now; loop lowering (jump offsets, landing pads) arrives with the loop tests.
enum ScriptCompiler {
    static func compile(_ script: Script) -> [Instruction] {
        script.bricks.map(Instruction.brick)
    }
}
