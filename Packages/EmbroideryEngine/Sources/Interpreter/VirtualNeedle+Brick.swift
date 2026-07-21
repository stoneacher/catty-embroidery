import EmbroideryEngine
import ProgramModel

public extension VirtualNeedle {
    /// Applies one motion brick, evaluating its formulas against `scope`, and
    /// returns the single `NeedleUpdate` the motion produces (US-204 AC 4). The
    /// needle is the pattern input, so exactly one update is emitted per executed
    /// motion brick — including the catch-and-skip cases below, where it carries
    /// the *unchanged* state.
    ///
    /// Returns `nil` **iff** `brick` is not a motion brick — a classification
    /// signal (US-205's stepper dispatches control/data/embroidery bricks
    /// elsewhere), never "no update needed" and never a crash.
    ///
    /// Bad-formula fallback is **per-brick**, mirroring the corresponding Catroid
    /// action — there is no universal "needle unchanged" rule:
    /// - `moveNSteps` / `turnLeft` / `turnRight` / `pointInDirection` / `setX` /
    ///   `setY` / `changeXBy` / `changeYBy` **catch and skip** the mutation
    ///   (Catroid's `MoveNStepsAction` etc. are catch-and-skip `TemporalAction`s),
    ///   but still emit the one update carrying the unchanged state.
    /// - `placeAt` **substitutes 0 per failed coordinate** (Catroid's
    ///   `createPlaceAtAction` is a `GlideToAction` whose failed x/y interpretation
    ///   becomes `0f`): a bad x with a good y places the needle at `(0, y)`.
    ///
    /// Execution always continues.
    mutating func apply(_ brick: Brick, scope: some Scope) -> NeedleUpdate? {
        switch brick {
        case let .moveNSteps(steps):
            eval(steps, scope).map { moveNSteps($0) }
        case let .turnRight(degrees):
            eval(degrees, scope).map { turnRight($0) }
        case let .turnLeft(degrees):
            eval(degrees, scope).map { turnLeft($0) }
        case let .pointInDirection(degrees):
            eval(degrees, scope).map { pointInDirection($0) }
        case let .placeAt(x, y):
            // Per-coordinate zero-substitution, not all-or-nothing.
            placeAt(x: eval(x, scope) ?? 0, y: eval(y, scope) ?? 0)
        case let .setX(x):
            eval(x, scope).map { setX($0) }
        case let .setY(y):
            eval(y, scope).map { setY($0) }
        case let .changeXBy(dx):
            eval(dx, scope).map { changeXBy($0) }
        case let .changeYBy(dy):
            eval(dy, scope).map { changeYBy($0) }
        default:
            return nil
        }
        return NeedleUpdate(position: position, heading: heading)
    }

    /// Evaluates `formula`, mapping the sole `FormulaError` to `nil` so callers
    /// apply the per-brick fallback (skip, or substitute for `placeAt`).
    private func eval(_ formula: Formula, _ scope: some Scope) -> Double? {
        try? formula.interpretDouble(scope: scope)
    }
}
