import ProgramModel

/// A script compiled to a linear instruction array (ADR-008: the *model* stays
/// the flat paired brick list — compilation is interpreter-internal). Straight-
/// line bricks become one `.brick` each; loop and If control bricks lower to
/// jump instructions carrying absolute instruction indices (one instruction per
/// brick), mirroring Catty `CBBackend`'s flatten-to-instructions precedent
/// (`repeatBegin.endIndex + 1` is the forward-skip on exit; `loopEnd.beginIndex`
/// is the back-jump; `ifBegin`'s `falseTarget` and `endIndex`, ADR-049).
enum Instruction: Sendable {
    /// A brick that produces a Catroid action — motion / data / wait / embroidery.
    /// Executing one such instruction costs exactly one tick (ADR-018).
    case brick(Brick)

    /// `repeatLoop` head: reads its count on its own first act (after an acted tick,
    /// in the next one: US-323) and exits past `endIndex` (the matching `loopEnd`)
    /// when the count is exhausted. Zero-tick, except that a count read that runs
    /// nothing takes the tick (ADR-018).
    case repeatBegin(times: Formula, endIndex: Int)

    /// `forever` head: never exits on its own, so it carries no forward-skip
    /// target (unlike `repeatBegin`). Zero-tick bookkeeping.
    case foreverBegin

    /// `repeatUntil` head (Variables slice 4, ADR-049): checks `condition` on
    /// entering each iteration — after an acted tick, in the next one — and exits
    /// past `endIndex` (its `loopEnd`) when it holds, taking that tick; the `loopEnd`
    /// checks it again at the body's end. Otherwise zero-tick.
    case repeatUntilBegin(condition: Formula, endIndex: Int)

    /// Loop tail (`loopEnd`): back-jumps to its matching begin at `beginIndex`.
    /// Zero-tick bookkeeping.
    case loopEnd(beginIndex: Int)

    /// `ifThen`/`ifElse` head (Variables slice 3, ADR-049): reads the condition once
    /// and enters the then-branch, jumps to `falseTarget` (the else-branch's first
    /// instruction, or `endIndex` without one), or — when the condition does not
    /// interpret — jumps to `endIndex`, running neither branch. Zero-tick, but it
    /// waits for the next tick when an action already ran in this one.
    case ifBegin(condition: Formula, falseTarget: Int, endIndex: Int)

    /// The end of an If/Else's then-branch (its `elseBranch`): jumps over the
    /// else-branch to `endIndex`. Zero-tick.
    case jump(to: Int)

    /// `ifEnd`: zero-tick, except that an If which ran no action in the tick it was
    /// read in takes that tick (ADR-049).
    case ifEnd
}

/// Compiles a `Script` once into its linear instruction array with a single-pass
/// backpatch over a stack of open blocks. An unbalanced script (which
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
        // Stack of open blocks, indices into `instructions`, for backpatching each
        // begin once its end position is known. `validate()` above guarantees every
        // pop finds the kind it expects.
        var open: [OpenBlock] = []

        for brick in script.bricks {
            switch brick {
            case let .repeatLoop(times):
                open.append(.loop(begin: instructions.count))
                // endIndex is backpatched at the matching loopEnd.
                instructions.append(.repeatBegin(times: times, endIndex: 0))
            case .forever:
                open.append(.loop(begin: instructions.count))
                instructions.append(.foreverBegin)
            case let .repeatUntil(condition):
                open.append(.loop(begin: instructions.count))
                instructions.append(.repeatUntilBegin(condition: condition, endIndex: 0))
            case let .ifThen(condition), let .ifElse(condition):
                open.append(.conditional(begin: instructions.count, elseJump: nil))
                // Both targets are backpatched at the matching ifEnd.
                instructions.append(.ifBegin(condition: condition, falseTarget: 0, endIndex: 0))
            case .elseBranch:
                guard lowerElse(into: &instructions, open: &open) else { return [] }
            case .ifEnd:
                guard lowerIfEnd(into: &instructions, open: &open) else { return [] }
            case .loopEnd:
                guard case let .loop(beginIndex) = open.popLast() else { return [] }
                let endIndex = instructions.count
                instructions.append(.loopEnd(beginIndex: beginIndex))
                // Backpatch a repeat or repeat-until head so it can skip forward past
                // this loopEnd when it is done; forever has no forward-skip target.
                switch instructions[beginIndex] {
                case let .repeatBegin(times, _):
                    instructions[beginIndex] = .repeatBegin(times: times, endIndex: endIndex)
                case let .repeatUntilBegin(condition, _):
                    instructions[beginIndex] = .repeatUntilBegin(condition: condition, endIndex: endIndex)
                case .brick, .foreverBegin, .loopEnd, .ifBegin, .jump, .ifEnd:
                    break
                }
            // Listed, not defaulted: a new brick must be compiled deliberately.
            case .moveNSteps, .turnLeft, .turnRight, .pointInDirection, .placeAt, .setX, .setY,
                 .changeXBy, .changeYBy, .arc, .goThrough, .wait, .setVariable, .changeVariableBy, .stitch,
                 .setThreadColor, .runningStitch, .zigZagStitch, .tripleStitch, .sewUp,
                 .stopRunningStitch, .writeEmbroideryToFile:
                instructions.append(.brick(brick))
            }
        }
        return instructions
    }
}

extension ScriptCompiler {
    /// An If/Else's `elseBranch`: the then-branch ends in a `jump`, backpatched at the
    /// end. `false` only on a structure `validate()` has already refused.
    private static func lowerElse(into instructions: inout [Instruction], open: inout [OpenBlock]) -> Bool {
        guard case let .conditional(begin, _) = open.popLast() else { return false }
        open.append(.conditional(begin: begin, elseJump: instructions.count))
        instructions.append(.jump(to: 0))
        return true
    }

    /// An `ifEnd`: backpatches the head's two targets and the else's jump.
    private static func lowerIfEnd(into instructions: inout [Instruction], open: inout [OpenBlock]) -> Bool {
        guard case let .conditional(begin, elseJump) = open.popLast(),
              case let .ifBegin(condition, _, _) = instructions[begin]
        else { return false }
        let endIndex = instructions.count
        instructions.append(.ifEnd)
        instructions[begin] = .ifBegin(
            condition: condition,
            falseTarget: elseJump.map { $0 + 1 } ?? endIndex,
            endIndex: endIndex
        )
        if let elseJump {
            instructions[elseJump] = .jump(to: endIndex)
        }
        return true
    }
}

/// A block the compiler has opened and not yet closed.
private enum OpenBlock {
    case loop(begin: Int)
    /// An If, and the `jump` its `elseBranch` compiled to, once seen.
    case conditional(begin: Int, elseJump: Int?)
}
