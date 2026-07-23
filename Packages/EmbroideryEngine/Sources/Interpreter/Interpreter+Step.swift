import EmbroideryEngine
import ProgramModel

extension Interpreter {
    /// Advances one thread by exactly one action-producing instruction (ADR-018).
    /// Zero-tick loop bookkeeping (added with the loop story-commit) is folded in
    /// around it; here the loop simply runs the next brick, then keeps advancing
    /// so the thread is marked finished in the *same* tick its last brick executes
    /// (not a tick later) — matching Catroid `RepeatAction`'s same-tick close.
    mutating func stepThread(_ index: Int, into events: inout [InterpreterEvent]) {
        var executedAction = false
        while true {
            if threads[index].instructionPointer >= threads[index].instructions.count {
                threads[index].finished = true
                return
            }
            switch threads[index].instructions[threads[index].instructionPointer] {
            case let .brick(brick):
                if executedAction {
                    return
                } // next action → defer to the next tick
                perform(brick, objectIndex: threads[index].objectIndex, into: &events)
                threads[index].instructionPointer += 1
                executedAction = true
            }
        }
    }

    /// Executes one brick against its object's runtime. Motion bricks go through
    /// the US-204 bridge (`VirtualNeedle.apply`), which applies the per-brick
    /// bad-formula fallback and always emits exactly one update; a non-motion
    /// brick returns `nil` and is dispatched here. Data bricks write the variable
    /// store; wait / embroidery handling arrives in later story-commits (a still-
    /// unhandled non-motion brick simply advances — US-206 wires embroidery).
    mutating func perform(_ brick: Brick, objectIndex: Int, into events: inout [InterpreterEvent]) {
        let scope = scope(forObjectAt: objectIndex)
        if let update = objects[objectIndex].needle.apply(brick, scope: scope) {
            events.append(.needleMoved(actor: objects[objectIndex].actorID, update: update))
            return
        }
        switch brick {
        case let .setVariable(name, valueFormula):
            // Throwing data formula substitutes 0 (Catroid data actions read
            // through interpretDouble, which returns 0 on failure) — distinct
            // from motion catch-and-skip.
            let value = (try? valueFormula.interpretDouble(scope: scope)) ?? 0
            setVariable(name, to: value, objectIndex: objectIndex)
        case let .changeVariableBy(name, valueFormula):
            // Throwing → add 0, i.e. a no-op that leaves the value intact.
            let delta = (try? valueFormula.interpretDouble(scope: scope)) ?? 0
            let current = scope.value(of: name)
            setVariable(name, to: current + delta, objectIndex: objectIndex)
        default:
            break
        }
    }

    /// Writes `value` to `name`, resolving which store it belongs to: an
    /// object-declared name writes the object store, a project-declared name the
    /// project store, an as-yet-unknown name is created object-local (Catroid
    /// sprite-first `UserDataWrapper` resolution).
    mutating func setVariable(_ name: String, to value: Double, objectIndex: Int) {
        if objects[objectIndex].variables[name] != nil {
            objects[objectIndex].variables[name] = value
        } else if projectVariables[name] != nil {
            projectVariables[name] = value
        } else {
            objects[objectIndex].variables[name] = value
        }
    }

    /// Builds the read scope for the object at `index`: its variables shadow the
    /// project variables (Catroid sprite-first resolution).
    func scope(forObjectAt index: Int) -> VariableStoreScope {
        VariableStoreScope(
            objectVariables: objects[index].variables,
            projectVariables: projectVariables
        )
    }
}
