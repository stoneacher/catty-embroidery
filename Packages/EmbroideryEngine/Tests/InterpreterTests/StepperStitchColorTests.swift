import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// ADR-021's producer half: `InterpreterEvent.stitch` carries the colour the
/// engine resolved, so the preview never reasons about thread colour itself.
///
/// Every program here needs **two** bricks at minimum. `setThreadColor` alone
/// emits only `.colorArmed` and never a `.stitch`, and a lone stitch brick has
/// no non-default colour to observe — so a one-brick program cannot show the
/// payload is wired to anything.
@Suite("Stepper stitch color")
struct StepperStitchColorTests {
    private let clock = InterpreterClock(tickDelta: 0.05)
    private let blue = ThreadColor(red: 0x1D, green: 0x4E, blue: 0xD8)
    private let amber = ThreadColor(red: 0xF5, green: 0x9E, blue: 0x0B)

    private func interpreter(_ bricks: [Brick]) -> Interpreter {
        Interpreter(
            program: Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: bricks)])])]),
            clock: clock
        )
    }

    @Test("a stitch after a color set carries that color")
    func stitchCarriesTheSetColor() {
        var interpreter = interpreter([.setThreadColor(hex: "#1d4ed8"), .stitch])
        let events = interpreter.run(maxTicks: 100)
        #expect(stitchColors(events) == [blue])
    }

    /// ADR-015's invalid-hex rule, inherited rather than implemented: the set is
    /// a full no-op, so the stitch carries the unchanged default.
    @Test("an invalid hex leaves the stitch color at the default")
    func invalidHexLeavesTheDefaultColor() {
        var interpreter = interpreter([.setThreadColor(hex: "not-a-color"), .stitch])
        let events = interpreter.run(maxTicks: 100)
        #expect(stitchColors(events) == [.black])
    }

    /// The colour must be read per `emitStitches` call, not once per run. With
    /// two colour blocks the partition falls at a known event index; an
    /// implementation resolving the colour once at construction would paint
    /// every stitch blue and still pass the single-colour test above.
    @Test("a mid-program color set partitions the stitch colors at the right index")
    func midProgramColorSetPartitionsTheStitches() {
        var interpreter = interpreter([
            .setThreadColor(hex: "#1d4ed8"),
            .stitch,
            .stitch,
            .setThreadColor(hex: "#f59e0b"),
            .stitch,
            .stitch
        ])
        let events = interpreter.run(maxTicks: 100)
        #expect(stitchColors(events) == [blue, blue, amber, amber])
    }

    /// The default is black, and it reaches the event — so "black in the display
    /// list" is a legitimate colour, not a marker for the export model's
    /// clause-B records (ADR-021's own correction).
    @Test("a stitch with no color set at all carries black")
    func unsetColorIsBlack() {
        var interpreter = interpreter([.stitch, .stitch])
        let events = interpreter.run(maxTicks: 100)
        #expect(stitchColors(events) == [.black, .black])
    }

    /// `.colorArmed` still reports the brick's raw *intent* — including for the
    /// invalid hex the manager rejected. That divergence is exactly why no
    /// preview path may consume it.
    @Test("colorArmed still reports the raw brick hex the manager rejected")
    func colorArmedIsUnchangedAndDivergesFromTheStitchColor() {
        var interpreter = interpreter([.setThreadColor(hex: "not-a-color"), .stitch])
        let events = interpreter.run(maxTicks: 100)
        #expect(colorArmedHexes(events) == ["not-a-color"])
        #expect(stitchColors(events) == [.black])
    }
}
