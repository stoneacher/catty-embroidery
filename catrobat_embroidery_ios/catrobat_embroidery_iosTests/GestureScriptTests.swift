@testable import catrobat_embroidery_ios
import CoreGraphics
import Testing

/// US-316's scripted gesture: where the driver's pan and pinch are at each moment (brief D4).
///
/// **A function of time, not of how often it was asked.** The driver samples it at each display
/// link's `targetTimestamp`, so a stalled frame makes the next sample jump the way a moving
/// finger does instead of slowing the gesture down to the renderer's pace.
struct GestureScriptTests {
    private static let frame = 1.0 / 60.0
    private static let samples = (0 ..< 12 * 60).map { Double($0) * frame }

    /// A recogniser reports translation from where the touch began and scale from 1, so the
    /// first sample must not jump.
    @Test("a gesture starts where a recogniser starts", arguments: [GestureScript.Kind.pan, .mixed])
    func startsAtRest(_ kind: GestureScript.Kind) {
        let script = GestureScript(kind: kind)
        #expect(script.translation(at: 0) == .zero)
        #expect(script.scale(at: 0) == 1)
    }

    @Test("a pan-only script never changes the scale")
    func panKeepsScale() {
        let script = GestureScript(kind: .pan)
        #expect(Self.samples.allSatisfy { script.scale(at: $0) == 1 })
    }

    @Test("the mixed script pinches as well as pans")
    func mixedPinches() {
        let script = GestureScript(kind: .mixed)
        let scales = Self.samples.map { script.scale(at: $0) }
        #expect(scales.contains { $0 > 1.1 })
        #expect(scales.contains { $0 < 0.9 })
        #expect(scales.allSatisfy { $0 >= 0.75 && $0 <= 1.25 })
    }

    /// Continuous, and moving: every frame at 60 Hz moves the design (so every frame redraws)
    /// by a bounded step (so no frame is a teleport a finger could not make).
    @Test("every 60 Hz step moves, by a bounded amount", arguments: [GestureScript.Kind.pan, .mixed])
    func boundedSteps(_ kind: GestureScript.Kind) {
        let script = GestureScript(kind: kind)
        for (earlier, later) in zip(Self.samples, Self.samples.dropFirst()) {
            let from = script.translation(at: earlier)
            let to = script.translation(at: later)
            let step = hypot(to.x - from.x, to.y - from.y)
            #expect(step > 0.1, "stalls at \(earlier) s")
            #expect(step <= 6, "jumps \(step) pt at \(earlier) s")
        }
    }

    /// The design stays in view: the pan never carries it further than this from where the
    /// gesture began.
    @Test("the pan stays within a bounded distance", arguments: [GestureScript.Kind.pan, .mixed])
    func staysClose(_ kind: GestureScript.Kind) {
        let script = GestureScript(kind: kind)
        #expect(Self.samples.allSatisfy {
            let point = script.translation(at: $0)
            return abs(point.x) <= 160 && abs(point.y) <= 160
        })
    }

    /// The property the driver relies on: sampling late lands where the gesture *is*, not
    /// one step on from where the last sample was.
    @Test("a skipped frame jumps rather than slows")
    func skippedFrameJumps() {
        let script = GestureScript(kind: .pan)
        let start = script.translation(at: 1)
        let oneStep = script.translation(at: 1 + Self.frame)
        let threeSteps = script.translation(at: 1 + 3 * Self.frame)
        let one = hypot(oneStep.x - start.x, oneStep.y - start.y)
        let three = hypot(threeSteps.x - start.x, threeSteps.y - start.y)
        #expect(three > 2.5 * one)
    }
}
