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

    public init(program: Program, clock: InterpreterClock) {
        self.clock = clock

        var objects: [ObjectRuntime] = []
        var threads: [ScriptThread] = []
        var projectVariables: [String: Double] = [:]
        for variable in program.variables {
            projectVariables[variable.name] = variable.value
        }

        // Flatten scenes → objects in creation order; ActorID is the global
        // object index (ADR-018). One thread per whenStarted script, object order
        // then script order.
        var objectIndex = 0
        for scene in program.scenes {
            for object in scene.objects {
                var objectVariables: [String: Double] = [:]
                for variable in object.variables {
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
                for script in object.scripts where script.header == .whenStarted {
                    threads.append(ScriptThread(
                        objectIndex: objectIndex,
                        instructions: ScriptCompiler.compile(script)
                    ))
                }
                objectIndex += 1
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
        for index in threads.indices where !threads[index].finished {
            stepThread(index, into: &events)
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
        threads.allSatisfy(\.finished)
    }
}
