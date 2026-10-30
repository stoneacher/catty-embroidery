@testable import catrobat_embroidery_ios
import Testing

/// US-316's per-frame signposts are opt-in (`-US316FrameSignposts`).
///
/// About 21 intervals a frame at 60 Hz overflowed the recorder's signpost buffer in a 2-minute
/// hand run: only its last 0.7 s of intervals survived, and the `capture` window's Begin with
/// them (2026-10-29). D6's runs need only the window and the result, so the per-frame intervals
/// are recorded only for D9's attribution runs.
struct StageSignpostsTests {
    @Test("per-frame intervals are off unless the launch asks for them")
    func optIn() {
        #expect(!StageSignposts.recordsFrames(arguments: ["app"]))
        #expect(!StageSignposts.recordsFrames(arguments: ["app", "-US316Capture", "A0"]))
        #expect(StageSignposts.recordsFrames(arguments: ["app", "-US316Capture", "A0", "-US316FrameSignposts"]))
    }
}
