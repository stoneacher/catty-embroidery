import ProgramModel

/// The condition-driven heads of Variables slices 4 and 5 (ADR-049): RepeatUntil's entry check
/// and the truthiness rules of RepeatUntil and WaitUntil, which Catroid's two condition loops
/// do not share. Kept apart from `Interpreter+Step.swift` for its length.
extension Interpreter {
    /// A `repeatUntil` head (zero-tick, ADR-049). Reached afresh or by the back-jump, it
    /// behaves alike — `RepeatUntilAction` re-checks on every uninitialized act — so it keeps
    /// no state: it waits out a tick that already acted, then checks the condition before the
    /// iteration, and a holding condition leaves without running the body. Returns whether
    /// to keep folding.
    mutating func advanceRepeatUntil(
        _ index: Int,
        condition: Formula,
        endIndex: Int,
        tick: inout TickState
    ) -> Bool {
        if tick.acted {
            return false
        }
        if untilHolds(condition, index) {
            // Exiting at entry is `RepeatUntilAction` returning in that frame: the tick is
            // taken (decided 2026-10-20), as an action-free If's is.
            threads[index].instructionPointer = endIndex + 1
            tick.acted = true
        } else {
            threads[index].instructionPointer += 1
        }
        return true
    }

    /// Catroid's `interpretBoolean`, `interpretDouble(...).intValue() != 0`
    /// (`Formula.java:258-259`): truncated, so `0.5` does not hold; a condition that does not
    /// interpret does not hold either, and the brick keeps waiting (`WaitUntilAction.java:66-69`).
    mutating func waitUntilHolds(_ condition: Formula, _ index: Int) -> Bool {
        let scope = scope(forObjectAt: threads[index].objectIndex)
        return ((try? condition.interpretInteger(scope: scope)) ?? 0) != 0
    }

    /// `interpretDouble(...) != 0.0` (`RepeatUntilAction.kt:51`): not truncated, so `0.5`
    /// holds; a condition that does not interpret holds too, ending the loop (`:61-62`).
    mutating func untilHolds(_ condition: Formula, _ index: Int) -> Bool {
        let scope = scope(forObjectAt: threads[index].objectIndex)
        guard let value = try? condition.interpretDouble(scope: scope) else { return true }
        return value != 0
    }
}
