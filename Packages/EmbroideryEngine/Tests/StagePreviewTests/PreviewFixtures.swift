import EmbroideryEngine
import Interpreter
import ProgramModel
import StagePreview

// Shared fixtures for the StagePreview suites. Free functions, not suite
// members, so they don't count toward any one suite's type_body_length.

/// Namespaced rather than three module-scope `let`s called `red`/`green`/`blue`
/// — those are broad names to own in a shared test namespace, and
/// `StepperStitchColorTests` already keeps its equivalents `private`.
enum PreviewColor {
    static let red = ThreadColor(red: 255, green: 0, blue: 0)
    static let green = ThreadColor(red: 0, green: 255, blue: 0)
    static let blue = ThreadColor(red: 0, green: 0, blue: 255)
}

/// Folds per-tick batches the way US-306's driver will: accumulate the
/// stitches, carry the needle pose forward, and keep the last terminal marker.
/// This *is* the subject of the ADR-018 partition tests, so it lives here once
/// rather than being written out inside each of them.
func foldBatches(_ batches: [[InterpreterEvent]]) -> FoldedRun {
    var folded = FoldedRun()
    for events in batches {
        let batch = RunBatch.reducing(events, from: folded.needle)
        folded.stitches += batch.stitches
        folded.needle = batch.needle
        folded.requestedName = batch.requestedDesignName ?? folded.requestedName
    }
    return folded
}

/// The result of `foldBatches`. A struct rather than a 3-tuple: SwiftLint caps
/// tuples at two members, and the names are worth having at the call sites.
struct FoldedRun {
    var stitches: [PreviewStitch] = []
    var needle: PreviewNeedle?
    var requestedName: String?
}

/// ADR-018's M3 clock: one tick per frame at 60 fps.
let previewClock = InterpreterClock(tickDelta: 1.0 / 60.0)

func previewStitch(_ x: Double, _ y: Double, _ color: ThreadColor = .black) -> PreviewStitch {
    PreviewStitch(position: StagePoint(x: x, y: y), color: color)
}

func displayList(_ stitches: [PreviewStitch]) -> StitchDisplayList {
    var list = StitchDisplayList()
    list.append(contentsOf: stitches)
    return list
}

/// Every `.stitch` event folded into the display list, in emission order — the
/// projection the preview builds during a run.
func displayList(from events: [InterpreterEvent]) -> StitchDisplayList {
    var list = StitchDisplayList()
    list.append(contentsOf: RunBatch.reducing(events).stitches)
    return list
}

func interpreter(_ program: Program) -> Interpreter {
    Interpreter(program: program, clock: previewClock)
}

func singleObjectProgram(_ bricks: [Brick]) -> Program {
    Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: bricks)])])])
}

/// Every `.ticked` batch from a run, in order.
func tickBatches(_ interpreter: inout Interpreter) -> [[InterpreterEvent]] {
    var batches: [[InterpreterEvent]] = []
    while case let .ticked(events) = interpreter.step() {
        batches.append(events)
    }
    return batches
}

/// Two objects on **different layers**, serialized by a wait so the first
/// finishes before the second starts.
///
/// Serialized for the same reason as the one-layer fixture: ADR-018 round-robins
/// one action brick per thread per tick, and interleaving would fire the
/// layer-switch clauses on nearly every stitch. With one clean switch the
/// assembler emits exactly one layer boundary, which is the thing under test.
func twoLayersProgram(waitTicks: Int = 40) -> Program {
    serializedTwoObjectProgram(secondObjectLayer: 1, waitTicks: waitTicks)
}

/// Two objects on **one layer**, each with a non-black thread, where the second
/// waits long enough that the first finishes before it starts.
///
/// The wait is not decoration. ADR-018 round-robins one action brick per thread
/// per tick, so without it the two objects interleave and clause B fires on
/// nearly every stitch, making the record count underivable. With it there is
/// exactly one actor alternation on the layer, and therefore exactly one
/// clause-B pair to count.
///
/// Both colours are non-black on purpose: if either actor were black, the two
/// black clause-B records would be indistinguishable from ordinary stitches and
/// the test would prove only that extra records exist, not that they differ in
/// colour. Coordinates are small and ordinary so ADR-020 cannot reject — a
/// rejected emission is skipped whole by the replay, which would delete the
/// very records under test.
func twoActorsOnOneLayerProgram(waitTicks: Int = 40) -> Program {
    serializedTwoObjectProgram(secondObjectLayer: 0, waitTicks: waitTicks)
}

/// The shared body of the two fixtures above: a red object that stitches twice,
/// then — after a wait long enough to guarantee it has finished — a green one
/// that does the same. `secondObjectLayer` is the *only* thing that differs
/// between them, and it is what selects which divergence the test observes:
/// layer 0 puts both actors on one layer (clause B), layer 1 makes it a layer
/// boundary. Kept as one builder so the two cannot drift apart in some
/// unrelated way and quietly stop being comparable.
private func serializedTwoObjectProgram(secondObjectLayer: Int, waitTicks: Int) -> Program {
    let first = Object(
        name: "First",
        startX: 0,
        startY: 0,
        zIndex: 0,
        scripts: [Script(bricks: [
            .setThreadColor(hex: "#ff0000"),
            .placeAt(x: .number(0), y: .number(0)),
            .stitch,
            .placeAt(x: .number(10), y: .number(0)),
            .stitch
        ])]
    )
    let second = Object(
        name: "Second",
        startX: 20,
        startY: 20,
        zIndex: secondObjectLayer,
        scripts: [Script(bricks: [
            .wait(seconds: .number(Double(waitTicks) * previewClock.tickDelta)),
            .setThreadColor(hex: "#00ff00"),
            .placeAt(x: .number(20), y: .number(20)),
            .stitch,
            .placeAt(x: .number(30), y: .number(20)),
            .stitch
        ])]
    )
    return Program(scenes: [Scene(objects: [first, second])])
}
