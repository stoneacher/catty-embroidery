import EmbroideryEngine
import ProgramModel

/// Runs a `Program` headlessly, one tick at a time, against an injected logical
/// clock (ADR-016, ADR-018). The `Interpreter` target is the only place the
/// program model and the embroidery engine meet: it maps `ProgramModel` objects
/// onto engine actors (object → `ActorID`, `zIndex` → layer), converts plain
/// `Double` positions to `StagePoint`, and (from US-206) parses hex colors.
///
/// A pure value type: all execution state — per-object needle and variable
/// store, per-thread program counters, loop counters, wait state, and the clock
/// cursor — lives inside the value. No globals, no reference types, so a caller
/// can snapshot or replay a run by copying the value. `run(maxTicks:)` equals the
/// concatenation of `step()` batches (the M2 exit-criterion equivalence).
public struct Interpreter: Sendable {
    let clock: InterpreterClock
    var objects: [ObjectRuntime]
    var projectVariables: [String: Double]
    var threads: [ScriptThread]
    /// The single sink every object's stitches feed (Catroid: the stage-wide
    /// `embroideryPatternManager`). Owns dedup / interpolation / color-change /
    /// layer assembly — the interpreter only calls it (ADR-012/013/015, US-206).
    var manager = EmbroideryPatternManager()
    /// The language-test harness's ending, if one was reached (brief D5).
    var harness = HarnessState()
    /// The ticks run so far; the current one while `step()` runs. A WaitTillIdle
    /// reads which threads finished in it (brief D8).
    var currentTick = 0

    public init(program: Program, clock: InterpreterClock) {
        // Flatten scenes → objects in creation order; ActorID is the global
        // object index (ADR-018). One thread per whenStarted script, object order
        // then script order.
        let objects = program.scenes.flatMap(\.objects).map { object in
            HarnessObject(object, scripts: object.scripts.filter { $0.header == .whenStarted }
                .map { $0.bricks.map(ScriptStep.brick) })
        }
        self.init(objects: objects, variables: program.variables, clock: clock)
    }

    /// The one construction path: each object with its scripts as step lists;
    /// an `Object`'s own `scripts` are ignored here, the steps replace them.
    init(objects programObjects: [HarnessObject], variables: [Variable], clock: InterpreterClock) {
        self.clock = clock

        var objects: [ObjectRuntime] = []
        var threads: [ScriptThread] = []
        // First declaration of a name wins, matching `ProgramModel.VariableScope`
        // (name uniqueness is the editor's job, not the model's — Scope.swift); a
        // plain dictionary assignment would let a later duplicate shadow the first.
        var projectVariables: [String: Double] = [:]
        for variable in variables where projectVariables[variable.name] == nil {
            projectVariables[variable.name] = variable.value
        }

        for (objectIndex, harnessObject) in programObjects.enumerated() {
            let object = harnessObject.object
            var objectVariables: [String: Double] = [:]
            for variable in object.variables where objectVariables[variable.name] == nil {
                objectVariables[variable.name] = variable.value
            }
            objects.append(ObjectRuntime(
                needle: VirtualNeedle(
                    position: StagePoint(x: object.startX, y: object.startY),
                    heading: object.startHeading
                ),
                variables: objectVariables,
                actorID: ActorID(objectIndex),
                layer: object.zIndex
            ))
            for (scriptIndex, steps) in harnessObject.scripts.enumerated() {
                threads.append(ScriptThread(
                    objectIndex: objectIndex,
                    scriptIndex: scriptIndex,
                    instructions: ScriptCompiler.compile(steps)
                ))
            }
        }

        self.objects = objects
        self.threads = threads
        self.projectVariables = projectVariables
    }

    /// Advances every runnable thread by one tick, returning the events produced
    /// in execution order, or `.finished` once no runnable thread remains.
    public mutating func step() -> StepOutcome {
        if isFinished {
            return .finished
        }
        var events: [InterpreterEvent] = []
        currentTick += 1
        for index in threads.indices where !threads[index].finished {
            stepThread(index, into: &events)
        }
        // A language test's ending finishes the tick it lands in, then the run
        // stops (brief D5): every other thread has taken this tick's action.
        if harness.ending != nil {
            harness.stopped = true
        }
        return .ticked(events)
    }

    /// Advances up to `maxTicks` ticks, returning every event produced, in order.
    /// Stops early once finished; `maxTicks <= 0` returns `[]`. The result is the
    /// concatenation of the `step()` batches, so batch and step-by-step agree.
    public mutating func run(maxTicks: Int) -> [InterpreterEvent] {
        var events: [InterpreterEvent] = []
        var ticks = 0
        while ticks < maxTicks {
            switch step() {
            case .finished:
                return events
            case let .ticked(batch):
                events.append(contentsOf: batch)
            }
            ticks += 1
        }
        return events
    }

    /// `true` once no runnable thread remains (vacuously true for a program with
    /// no whenStarted scripts).
    public var isFinished: Bool {
        harness.stopped || threads.allSatisfy(\.finished)
    }

    /// The embroidery stream assembled from every stitch produced so far
    /// (`EmbroideryPatternManager.assembled()`): layers replayed in ascending
    /// z-order, interpolation and unit conversion run once (US-206, AC 7). Pure
    /// — callable at any point; running further ticks and re-assembling reflects
    /// the added stitches.
    public func assembledStream() -> EmbroideryStream {
        manager.assembled()
    }
}
