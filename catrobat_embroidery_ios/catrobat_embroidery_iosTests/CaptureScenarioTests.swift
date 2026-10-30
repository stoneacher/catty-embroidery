@testable import catrobat_embroidery_ios
import Samples
import Testing

/// US-316's capture scenario: what one launch argument asks the app to measure (brief D1, D5).
///
/// The parser takes the argument list rather than reading `ProcessInfo`, so every rule here is
/// a value test, and an ordinary launch (no argument) is the first case pinned: without it the
/// driver never registers, and the parallel suites never touch it.
struct CaptureScenarioTests {
    @Test("no argument means no capture")
    func absent() {
        #expect(CaptureScenario.parse(["app"]) == nil)
        #expect(CaptureScenario.parse(["app", "-US310FrameTimes"]) == nil)
    }

    @Test("each condition parses to its fixture, gesture, control and zoom",
          arguments: [
              ("A0", SampleID.us309Synthetic, GestureScript.Kind.pan, LiveDrawControl.none, false),
              ("B", .us316Compact, .pan, .none, false),
              ("C", .us309Synthetic, .pan, .none, true),
              ("D", .us309Synthetic, .pan, .noDots, false),
              ("E", .us309Synthetic, .pan, .noThread, false),
              ("A0-mixed", .us309Synthetic, .mixed, .none, false)
          ])
    func conditions(
        _ token: String, _ sample: SampleID, _ gesture: GestureScript.Kind,
        _ control: LiveDrawControl, _ zoomedOut: Bool
    ) throws {
        let scenario = try #require(CaptureScenario.parse(["app", "-US316Capture", token]))
        #expect(scenario.condition.rawValue == token)
        #expect(scenario.condition.sample == sample)
        #expect(scenario.condition.gesture == gesture)
        #expect(scenario.condition.liveControl == control)
        #expect((scenario.condition.zoomRelativeToFit != nil) == zoomedOut)
        #expect(scenario.holdSeconds == 12)
    }

    @Test("an unknown or missing condition is not a capture")
    func unknown() {
        #expect(CaptureScenario.parse(["app", "-US316Capture", "F"]) == nil)
        #expect(CaptureScenario.parse(["app", "-US316Capture", "a0"]) == nil)
        #expect(CaptureScenario.parse(["app", "-US316Capture"]) == nil)
    }

    @Test("the hold can be lengthened, never to a window shorter than the bar's ten seconds")
    func hold() {
        #expect(CaptureScenario.parse(["app", "-US316Capture", "B", "-US316Hold", "15"])?.holdSeconds == 15)
        #expect(CaptureScenario.parse(["app", "-US316Capture", "B", "-US316Hold", "10.5"])?.holdSeconds == 10.5)
        // Exactly ten is refused: the recorder's first callback times nothing, so a 10 s hold
        // records a 9.9 s window, which the bar cannot quote (the slice's simulator dry run).
        #expect(CaptureScenario.parse(["app", "-US316Capture", "B", "-US316Hold", "10"]) == nil)
        #expect(CaptureScenario.parse(["app", "-US316Capture", "B", "-US316Hold", "9.9"]) == nil)
        #expect(CaptureScenario.parse(["app", "-US316Capture", "B", "-US316Hold", "5"]) == nil)
        #expect(CaptureScenario.parse(["app", "-US316Capture", "B", "-US316Hold", "long"]) == nil)
        #expect(CaptureScenario.parse(["app", "-US316Capture", "B", "-US316Hold"]) == nil)
    }

    /// D1/D3: condition C is taken where the design covers at most a tenth of A0's view area.
    @Test("the zoomed-out condition covers at most a tenth of the fitted area")
    func zoomCoversATenth() throws {
        let factor = try #require(CaptureCondition.zoomedOut.zoomRelativeToFit)
        #expect(factor > 0)
        #expect(factor * factor <= 0.1)
    }

    /// D7's fallback takes the matrix by hand, D and E included, so the live control must be
    /// reachable without the driver: `-US316Hand` keeps the condition's control and fixture but
    /// asks for no unattended session (`swift-code-reviewer`, slices 2–4).
    @Test("a hand run keeps its condition but asks for no session")
    func handRun() throws {
        let scenario = try #require(CaptureScenario.parse(["app", "-US316Capture", "D", "-US316Hand"]))
        #expect(scenario.isByHand)
        #expect(scenario.condition.liveControl == .noDots)
        #expect(CaptureScenario.parse(["app", "-US316Capture", "D"])?.isByHand == false)
        #expect(LiveDrawControl.from(arguments: ["app", "-US316Capture", "E", "-US316Hand"]) == .noThread)
    }

    /// A hand run ends the app a second after Stop, so `xctrace --launch` stops recording right
    /// behind the window. The recorder keeps a trailing window of what it records; in a hand run
    /// that went on recording for a minute after Stop, the whole capture had fallen out of the
    /// trace (2026-10-29). A plain launch and a scripted run (which exits on its own) do not.
    @Test("only a hand run exits after the capsule's Stop")
    func handRunExitsAfterStop() {
        #expect(CaptureScenario.exitsAfterHandStop(arguments: ["app", "-US316Capture", "A0", "-US316Hand"]))
        #expect(!CaptureScenario.exitsAfterHandStop(arguments: ["app", "-US316Capture", "A0"]))
        #expect(!CaptureScenario.exitsAfterHandStop(arguments: ["app"]))
        #expect(!CaptureScenario.exitsAfterHandStop(arguments: ["app", "-US310FrameTimes"]))
    }
}
