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
            case let .repeatBegin(times, endIndex):
                // Entering a *new* iteration after an action already ran this tick
                // defers to the next tick (the next iteration's first brick, one
                // per tick). Exhausting the loop is not a new iteration, so it
                // folds into this tick — that is the same-tick finish.
                if enterRepeat(index, times: times, endIndex: endIndex, deferEntry: executedAction) {
                    return
                }

            case .foreverBegin:
                if executedAction {
                    return
                } // defer the next iteration to the next tick
                threads[index].instructionPointer += 1 // zero-tick; never exits itself

            case let .loopEnd(beginIndex):
                // Close the iteration by jumping back to the matching begin. An
                // action-free iteration (e.g. `forever {}` in isolation) reaches
                // here with no action this tick, so the back-jump itself consumes
                // the tick — one empty iteration per tick (libgdx one-act-per-tick),
                // never a spin. When an action did run, the begin guards above stop
                // the fold at the next iteration's entry.
                threads[index].instructionPointer = beginIndex
                if !executedAction {
                    return
                }

            case let .brick(brick):
                if executedAction {
                    return
                } // next action → defer to the next tick
                if case let .wait(seconds) = brick {
                    let completed = advanceWait(index, seconds: seconds, into: &events)
                    executedAction = true
                    if completed {
                        threads[index].instructionPointer += 1
                    } else {
                        return // still waiting — pointer stays on the wait
                    }
                } else {
                    perform(brick, objectIndex: threads[index].objectIndex, into: &events)
                    threads[index].instructionPointer += 1
                    executedAction = true
                }
            }
        }
    }

    /// Advances the blocking `wait` on the thread at `index` by one tick,
    /// returning whether it completed this tick. The duration is resolved lazily
    /// on first arrival via `interpretDouble` (throw → 0, Catroid `WaitAction`
    /// duration-0 fallback); `elapsed` accumulates `tickDelta` and the wait
    /// completes once `elapsed >= duration` (checked after the add, Catroid
    /// `TemporalAction`), emitting one `.waited`. `interpretDouble` — not Catroid's
    /// Float-API `interpretFloat` — keeps the Double clock exact (ADR-018).
    private mutating func advanceWait(_ index: Int, seconds: Formula, into events: inout [InterpreterEvent]) -> Bool {
        if threads[index].wait == nil {
            let scope = scope(forObjectAt: threads[index].objectIndex)
            let duration = (try? seconds.interpretDouble(scope: scope)) ?? 0
            threads[index].wait = WaitState(duration: duration, elapsed: 0)
        }
        threads[index].wait?.elapsed += clock.tickDelta
        guard let state = threads[index].wait, state.elapsed >= state.duration else {
            return false
        }
        events.append(.waited(actor: objects[threads[index].objectIndex].actorID))
        threads[index].wait = nil
        return true
    }

    /// Processes a `repeatBegin` (zero-tick): initializes its counter on first
    /// arrival (throw / negative / zero count → 0 iterations, Catroid
    /// `RepeatAction` parity), then either exits past the matching `loopEnd`
    /// (clearing the counter so a nesting outer loop reinits it) or enters the
    /// body. Returns `true` when the caller should yield the tick: an as-yet-
    /// unstarted iteration (`deferEntry`) is deferred to the next tick, leaving
    /// the pointer and counter untouched. Exhaustion never yields.
    private mutating func enterRepeat(_ index: Int, times: Formula, endIndex: Int, deferEntry: Bool) -> Bool {
        let pointer = threads[index].instructionPointer
        let remaining: Int
        if let existing = threads[index].loopCounters[pointer] {
            remaining = existing
        } else {
            let scope = scope(forObjectAt: threads[index].objectIndex)
            remaining = max(0, (try? times.interpretInteger(scope: scope)) ?? 0)
        }
        if remaining <= 0 {
            threads[index].loopCounters[pointer] = nil
            threads[index].instructionPointer = endIndex + 1
            return false
        }
        if deferEntry {
            return true // next iteration starts next tick; counter/pointer untouched
        }
        threads[index].loopCounters[pointer] = remaining - 1
        threads[index].instructionPointer += 1
        return false
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
