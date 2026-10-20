import EmbroideryEngine
import ProgramModel

extension Interpreter {
    /// Advances one thread by exactly one action-producing instruction (ADR-018).
    /// Zero-tick bookkeeping — loop heads and ends, If heads, else-jumps and If ends
    /// (ADR-049) — is folded in around it, and the thread keeps advancing so it is
    /// marked finished in the *same* tick its last brick executes (not a tick later),
    /// matching Catroid `RepeatAction`'s same-tick close.
    mutating func stepThread(_ index: Int, into events: inout [InterpreterEvent]) {
        var tick = TickState()
        while threads[index].instructionPointer < threads[index].instructions.count {
            guard advance(index, tick: &tick, into: &events) else {
                return // yielded the tick
            }
        }
        // Ran off the end — folded into the same tick as the last action, so the
        // thread is marked finished now (not a tick later), matching Catroid
        // `RepeatAction`'s same-tick close.
        threads[index].finished = true
    }

    /// Processes the instruction under the pointer. Returns `true` to keep folding
    /// this tick (zero-tick bookkeeping, or an action that lets the fold continue
    /// to the loop close / end), `false` to yield the tick.
    private mutating func advance(_ index: Int, tick: inout TickState, into events: inout [InterpreterEvent]) -> Bool {
        switch threads[index].instructions[threads[index].instructionPointer] {
        case let .ifBegin(condition, falseTarget, endIndex):
            // Read on the If's own first act (Catroid `IfLogicAction`): after an action
            // this tick, the read waits for the next one.
            if tick.acted {
                return false
            }
            tick.readIf = true
            let scope = scope(forObjectAt: threads[index].objectIndex)
            // `interpretDouble(...).toInt() != 0` (`IfLogicAction.kt:43`); a condition
            // that does not interpret runs neither branch (`:56-57`).
            if let value = try? condition.interpretInteger(scope: scope) {
                threads[index].instructionPointer = value != 0 ? threads[index].instructionPointer + 1 : falseTarget
            } else {
                threads[index].instructionPointer = endIndex
            }
            return true

        case let .jump(target):
            threads[index].instructionPointer = target
            return true

        case .ifEnd:
            // An If read in this tick whose branch ran no action takes the tick, as an
            // empty If is one frame of Catroid's sequence. Only one: an inner If's end has
            // already taken it, so nested empty Ifs cost one tick in total, and an If read
            // in an earlier tick costs nothing more here (ADR-049).
            if tick.readIf {
                tick.acted = true
            }
            threads[index].instructionPointer += 1
            return true

        case let .repeatBegin(times, endIndex):
            // Entering a *new* iteration after an action already ran this tick
            // defers to the next tick (the next iteration's first brick, one per
            // tick). Exhausting the loop is not a new iteration, so it folds into
            // this tick — that is the same-tick finish.
            return !enterRepeat(index, times: times, endIndex: endIndex, deferEntry: tick.acted)

        case .foreverBegin:
            if tick.acted {
                return false
            } // defer the next iteration to the next tick
            threads[index].instructionPointer += 1 // zero-tick; never exits itself
            return true

        case let .repeatUntilBegin(condition, endIndex):
            return advanceRepeatUntil(index, condition: condition, endIndex: endIndex, tick: &tick)

        case let .loopEnd(beginIndex):
            // A repeat-until checks its condition at the body's end, in the tick of its last
            // brick, and leaves there when it holds (`RepeatUntilAction.kt:72-75`).
            if case let .repeatUntilBegin(condition, endIndex) = threads[index].instructions[beginIndex],
               untilHolds(condition, index) {
                threads[index].instructionPointer = endIndex + 1
                return true
            }
            // Close the iteration by jumping back to the matching begin. An
            // action-free iteration (e.g. `forever {}` in isolation) reaches here
            // with no action this tick, so the back-jump itself consumes the tick
            // — one empty iteration per tick (libgdx one-act-per-tick), never a
            // spin. When an action did run, the begin guards stop the fold at the
            // next iteration's entry.
            threads[index].instructionPointer = beginIndex
            return tick.acted

        case let .brick(brick):
            return performActionBrick(index, brick, acted: &tick.acted, into: &events)
        }
    }

    /// Executes one action-producing brick (motion / data / wait / embroidery),
    /// or defers it to the next tick if an action already ran this tick. Returns
    /// `true` to keep folding, `false` to yield (a deferred or still-blocking wait).
    private mutating func performActionBrick(
        _ index: Int,
        _ brick: Brick,
        acted: inout Bool,
        into events: inout [InterpreterEvent]
    ) -> Bool {
        if acted {
            return false
        } // next action → defer to the next tick
        if case let .wait(seconds) = brick {
            acted = true
            guard advanceWait(index, seconds: seconds, into: &events) else {
                return false // still waiting — pointer stays on the wait
            }
            threads[index].instructionPointer += 1
            return true
        }
        perform(brick, objectIndex: threads[index].objectIndex, into: &events)
        threads[index].instructionPointer += 1
        acted = true
        return true
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

    /// A `repeatUntil` head (zero-tick, ADR-049). Reached afresh or by the back-jump, it
    /// behaves alike — `RepeatUntilAction` re-checks on every uninitialized act — so it keeps
    /// no state: it waits out a tick that already acted, then checks the condition before the
    /// iteration, and a holding condition leaves without running the body. Returns whether
    /// to keep folding.
    private mutating func advanceRepeatUntil(
        _ index: Int,
        condition: Formula,
        endIndex: Int,
        tick: inout TickState
    ) -> Bool {
        if tick.acted {
            return false
        }
        threads[index].instructionPointer = untilHolds(condition, index)
            ? endIndex + 1
            : threads[index].instructionPointer + 1
        return true
    }

    /// `interpretDouble(...) != 0.0` (`RepeatUntilAction.kt:51`): not truncated, so `0.5`
    /// holds; a condition that does not interpret holds too, ending the loop (`:61-62`).
    private mutating func untilHolds(_ condition: Formula, _ index: Int) -> Bool {
        let scope = scope(forObjectAt: threads[index].objectIndex)
        guard let value = try? condition.interpretDouble(scope: scope) else { return true }
        return value != 0
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
        } else if deferEntry {
            // US-323 (ADR-018 amendment): read the count on the loop's own first act, in
            // the next tick, not in the tick of the action before it.
            return true
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

    /// Executes one brick against its object's runtime, in one exhaustive switch
    /// so a new brick cannot compile without being dispatched here. Motion bricks
    /// go through the US-204 bridge (`VirtualNeedle.apply`), which applies the
    /// per-brick bad-formula fallback and emits at least one update: exactly
    /// one for most motions, one per fed sample for Arc and GoThrough (ADR-047). Data
    /// bricks write the variable store; embroidery bricks (US-206) drive the
    /// engine — the interpreter only calls it, never re-implementing stream
    /// semantics (ADR-012/013/015).
    mutating func perform(_ brick: Brick, objectIndex: Int, into events: inout [InterpreterEvent]) {
        let scope = scope(forObjectAt: objectIndex)
        switch brick {
        case .moveNSteps, .turnLeft, .turnRight, .pointInDirection, .placeAt, .setX, .setY,
             .changeXBy, .changeYBy, .arc, .goThrough:
            performMotion(brick, objectIndex: objectIndex, scope: scope, into: &events)
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
        case let .runningStitch(length):
            // Pattern activators read the current needle position as their start
            // (Catroid actions construct the stitch reading `sprite.look`); zero /
            // negative / non-finite params are engine no-ops (ADR-014).
            // Length via interpretInteger (US-202 contract; Int32-saturating).
            let stitchLength = (try? length.interpretInteger(scope: scope)) ?? 0
            objects[objectIndex].runningStitch.activate(RunningStitchPattern(
                length: Double(stitchLength), start: objects[objectIndex].needle.position
            ))
        case let .zigZagStitch(length, width):
            // Length and width via interpretFloat (US-202 contract), widened to
            // the engine's Double — Catroid reads them as Java float (ADR-014).
            let zigLength = (try? length.interpretFloat(scope: scope)) ?? 0
            let zigWidth = (try? width.interpretFloat(scope: scope)) ?? 0
            objects[objectIndex].runningStitch.activate(ZigzagStitchPattern(
                length: Double(zigLength), width: Double(zigWidth), start: objects[objectIndex].needle.position
            ))
        case let .tripleStitch(length):
            let stitchLength = (try? length.interpretInteger(scope: scope)) ?? 0
            objects[objectIndex].runningStitch.activate(TripleStitchPattern(
                length: Double(stitchLength), start: objects[objectIndex].needle.position
            ))
        case .stitch:
            performStitch(objectIndex: objectIndex, into: &events)
        case .sewUp:
            // Catroid `SewUpAction`: 5-point bar tack around the needle. The
            // engine pauses, re-anchors, and resumes the running stitch itself.
            // Read the needle by value into locals first, so the call does not
            // depend on argument evaluation order preceding the `inout` access.
            let center = objects[objectIndex].needle.position
            let heading = objects[objectIndex].needle.heading
            let points = SewUp.perform(
                at: center, heading: heading, runningStitch: &objects[objectIndex].runningStitch
            )
            emitStitches(points, objectIndex: objectIndex, into: &events)
        case let .setThreadColor(hex):
            // The manager owns the change-record decision — invalid hex is a
            // full no-op, and a set before any emission silently selects the
            // starting color (ADR-015). `colorArmed` is the brick's *intent*,
            // emitted on every execution regardless of that decision.
            manager.setThreadColor(hexString: hex, for: objects[objectIndex].actorID)
            events.append(.colorArmed(actor: objects[objectIndex].actorID, hex: hex))
        case .stopRunningStitch:
            // Catroid `StopRunningStitchAction.deactivate`: discard the pattern,
            // so later motion emits nothing until a new activation.
            objects[objectIndex].runningStitch.stop()
        case let .writeEmbroideryToFile(name):
            // Modeled as a finalize marker only — the package performs no I/O
            // (milestone deviation table). The assembled stream is always
            // available via `assembledStream()`; the brick stays for M4/M5.
            events.append(.finalizeRequested(name: name))
        case .repeatLoop, .forever, .repeatUntil, .loopEnd, .wait, .ifThen, .ifElse, .elseBranch, .ifEnd:
            // Never dispatched here: loops and Ifs compile to instructions
            // (`ScriptCompiler`) and `wait` blocks in `performActionBrick`.
            break
        }
    }

    /// Catroid `StitchAction`: pause, place one point at the needle, re-anchor
    /// the running stitch there, resume.
    private mutating func performStitch(objectIndex: Int, into events: inout [InterpreterEvent]) {
        let point = objects[objectIndex].needle.position
        objects[objectIndex].runningStitch.pause()
        emitStitches([point], objectIndex: objectIndex, into: &events)
        objects[objectIndex].runningStitch.setStartPosition(point)
        objects[objectIndex].runningStitch.resume()
    }

    /// Moves the needle through the US-204 bridge and feeds each update to the
    /// running stitch — Catroid `Look.positionChanged → runningStitch.update`: an
    /// active pattern consumes the motion; an idle wrapper returns [] (no-op), so
    /// this is the documented once-per-update feed, not once-per-tick. An Arc's
    /// updates are fed one by one, each followed by its own stitches, all within
    /// the brick's single tick (ADR-047). A many-update action is fed as one
    /// path, so ADR-014's million-length bound covers the whole action
    /// (`RunningStitch.update(path:from:)`); a single update is fed as before.
    private mutating func performMotion(
        _ brick: Brick, objectIndex: Int, scope: VariableStoreScope, into events: inout [InterpreterEvent]
    ) {
        let start = objects[objectIndex].needle.position
        guard let updates = objects[objectIndex].needle.apply(brick, scope: scope) else {
            assertionFailure("perform routes motion bricks only")
            return
        }
        let stitchesPerUpdate = updates.count > 1
            ? objects[objectIndex].runningStitch.update(path: updates, from: start)
            : updates.map { objects[objectIndex].runningStitch.update($0) }
        for (update, stitches) in zip(updates, stitchesPerUpdate) {
            events.append(.needleMoved(actor: objects[objectIndex].actorID, update: update))
            emitStitches(stitches, objectIndex: objectIndex, into: &events)
        }
    }

    /// Sends each stage point to the shared manager (at the object's layer and
    /// actor) and emits a `.stitch` event — one event per `addStitch` call, the
    /// trace of the call (the stream's own dedup may later collapse consecutive
    /// duplicates; the event count reflects calls, not surviving stitches).
    private mutating func emitStitches(
        _ points: [StagePoint], objectIndex: Int, into events: inout [InterpreterEvent]
    ) {
        let actorID = objects[objectIndex].actorID
        let layer = objects[objectIndex].layer
        // Read once for the whole burst. `addStitch` cannot change the actor's
        // current color — it snapshots it up front and only clears the armed
        // bit (ADR-021) — and no brick runs between these points, so one read
        // is the same answer as one per point. Worth hoisting: a single tick
        // can emit 51 points in sample 1 and 106 in a triple-stitch design.
        let color = manager.threadColor(for: actorID)
        for point in points {
            manager.addStitch(at: point, layer: layer, actor: actorID)
            events.append(.stitch(actor: actorID, position: point, layer: layer, color: color))
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
            projectVariables: projectVariables,
            needle: objects[index].needle
        )
    }
}

/// What one thread's tick has done so far, threaded through `advance`.
private struct TickState {
    /// The tick is taken: an action ran (ADR-018: one per thread per tick), or an
    /// action-free If's end took it (ADR-049).
    var acted = false
    /// An If's condition was read this tick (ADR-049): its end then takes the tick if
    /// no action did.
    var readIf = false
}
