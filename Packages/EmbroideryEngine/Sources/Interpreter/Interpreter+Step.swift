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
            if threads[index].ip >= threads[index].instructions.count {
                threads[index].finished = true
                return
            }
            switch threads[index].instructions[threads[index].ip] {
            case let .brick(brick):
                if executedAction {
                    return
                } // next action → defer to the next tick
                perform(brick, objectIndex: threads[index].objectIndex, into: &events)
                threads[index].ip += 1
                executedAction = true
            }
        }
    }

    /// Executes one brick against its object's runtime. Motion bricks go through
    /// the US-204 bridge (`VirtualNeedle.apply`), which applies the per-brick
    /// bad-formula fallback and always emits exactly one update; a non-motion
    /// brick returns `nil` and is dispatched here. Data / wait / embroidery
    /// handling arrives in later story-commits; for now a non-motion brick simply
    /// advances (US-206 wires embroidery events).
    mutating func perform(_ brick: Brick, objectIndex: Int, into events: inout [InterpreterEvent]) {
        let scope = scope(forObjectAt: objectIndex)
        if let update = objects[objectIndex].needle.apply(brick, scope: scope) {
            events.append(.needleMoved(actor: objects[objectIndex].actorID, update: update))
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
