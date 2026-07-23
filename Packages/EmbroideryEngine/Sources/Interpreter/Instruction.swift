import ProgramModel

/// A script compiled to a linear instruction array (ADR-008: the *model* stays
/// the flat paired brick list — compilation is interpreter-internal). Straight-
/// line bricks become one `.brick` each; loop-control bricks lower to jump
/// instructions carrying relative targets, mirroring Catty `CBBackend`'s
/// flatten-to-instructions precedent (`repeatBegin.endIndex + 1` is the
/// forward-skip on exit; `loopEnd.beginIndex` is the back-jump).
enum Instruction: Sendable {
    /// A brick that produces a Catroid action — motion / data / wait / embroidery.
    /// Executing one such instruction costs exactly one tick (ADR-018).
    case brick(Brick)

    /// `repeatLoop` head: initializes its iteration counter on first arrival and
    /// exits past `endIndex` (the matching `loopEnd`) when the count is exhausted.
    /// Zero-tick bookkeeping.
    case repeatBegin(times: Formula, endIndex: Int)

    /// `forever` head: never exits on its own, so it carries no forward-skip
    /// target (unlike `repeatBegin`). Zero-tick bookkeeping.
    case foreverBegin

    /// Loop tail (`loopEnd`): back-jumps to its matching begin at `beginIndex`.
    /// Zero-tick bookkeeping.
    case loopEnd(beginIndex: Int)
}

/// Compiles a `Script` once into its linear instruction array with a single-pass
/// backpatch over a stack of open loops. An unbalanced script (which
/// `Script.validate()` rejects) compiles to an inert `[]` — no thread, never a
/// crash, consistent with the interpreter's never-halt contract (ADR-018).
enum ScriptCompiler {
    static func compile(_ script: Script) -> [Instruction] {
        do {
            try script.validate()
        } catch {
            return []
        }

        var instructions: [Instruction] = []
        instructions.reserveCapacity(script.bricks.count)
        // Stack of open-loop indices into `instructions`, for backpatching the
        // begin's endIndex once its loopEnd position is known.
        var openLoops: [Int] = []

        for brick in script.bricks {
            switch brick {
            case let .repeatLoop(times):
                openLoops.append(instructions.count)
                // endIndex is backpatched at the matching loopEnd.
                instructions.append(.repeatBegin(times: times, endIndex: 0))
            case .forever:
                openLoops.append(instructions.count)
                instructions.append(.foreverBegin)
            case .loopEnd:
                let beginIndex = openLoops.removeLast()
                let endIndex = instructions.count
                instructions.append(.loopEnd(beginIndex: beginIndex))
                // Backpatch a repeatBegin so it can skip forward past this loopEnd
                // when its count is exhausted; forever has no forward-skip target.
                if case let .repeatBegin(times, _) = instructions[beginIndex] {
                    instructions[beginIndex] = .repeatBegin(times: times, endIndex: endIndex)
                }
            default:
                instructions.append(.brick(brick))
            }
        }
        return instructions
    }
}
