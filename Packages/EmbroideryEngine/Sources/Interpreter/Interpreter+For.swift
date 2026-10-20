import ProgramModel

/// ForVariableFromTo (Variables slice 6, ADR-049; `ForVariableFromToAction.java:47-117`).
extension Interpreter {
    /// A `forBegin` head. On the loop's own first act — in the next tick if an action already
    /// ran in this one — it reads `from` and `to` once as `interpretDouble(...).intValue()`
    /// (`interpretInteger`: truncated, Int32-saturated), fixes the step at `+1` if `from ≤ to`
    /// else `−1`, writes `from` and enters the body, whose first brick runs in the same tick.
    /// Bounds that do not interpret skip the loop and leave the variable alone; that exit takes
    /// the tick, as Catroid's action returns in its first frame. Later arrivals, by the
    /// back-jump, wait out an acted tick and enter the next pass. Returns whether to keep
    /// folding.
    mutating func advanceFor(
        _ index: Int,
        name: String,
        bounds: (from: Formula, to: Formula),
        endIndex: Int,
        tick: inout TickState
    ) -> Bool {
        if tick.acted {
            return false
        }
        let pointer = threads[index].instructionPointer
        guard threads[index].forLoops[pointer] == nil else {
            threads[index].instructionPointer = pointer + 1
            return true
        }
        let scope = scope(forObjectAt: threads[index].objectIndex)
        guard let fromValue = try? bounds.from.interpretInteger(scope: scope),
              let toValue = try? bounds.to.interpretInteger(scope: scope)
        else {
            threads[index].instructionPointer = endIndex + 1
            tick.acted = true
            return true
        }
        let start = Double(fromValue)
        threads[index].forLoops[pointer] = ForLoopState(
            to: Double(toValue),
            step: fromValue <= toValue ? 1 : -1,
            hiddenValue: name.isEmpty ? start : nil
        )
        if !name.isEmpty {
            setVariable(name, to: start, objectIndex: threads[index].objectIndex)
        }
        threads[index].instructionPointer = pointer + 1
        return true
    }

    /// A pass's end, at the loop's `loopEnd`: re-reads the variable — an edit in the body
    /// counts — and exits if `step > 0 ∧ v ≥ to` or `step < 0 ∧ v ≤ to`, else adds the step and
    /// jumps back. An exit in a tick where nothing acted (an empty body) takes the tick, as
    /// Catroid's action returns in that frame; otherwise it folds into the tick of the body's
    /// last brick. Returns whether to keep folding.
    mutating func closeForPass(
        _ index: Int,
        name: String,
        beginIndex: Int,
        endIndex: Int,
        tick: inout TickState
    ) -> Bool {
        guard var state = threads[index].forLoops[beginIndex] else {
            // Unreachable: a pass's end is only reached through its head, which set the state.
            assertionFailure("a For loop's end was reached without its head's state")
            threads[index].instructionPointer = endIndex + 1
            return true
        }
        let objectIndex = threads[index].objectIndex
        let value = state.hiddenValue ?? scope(forObjectAt: objectIndex).value(of: name)
        if state.step > 0 ? value >= state.to : value <= state.to {
            threads[index].forLoops[beginIndex] = nil
            threads[index].instructionPointer = endIndex + 1
            tick.acted = true
            return true
        }
        if state.hiddenValue != nil {
            state.hiddenValue = value + state.step
            threads[index].forLoops[beginIndex] = state
        } else {
            setVariable(name, to: value + state.step, objectIndex: objectIndex)
        }
        threads[index].instructionPointer = beginIndex
        // After an acted pass, keep folding: the head defers the next pass itself. An action-free
        // pass yields here instead, so each empty pass costs one tick.
        return tick.acted
    }
}
