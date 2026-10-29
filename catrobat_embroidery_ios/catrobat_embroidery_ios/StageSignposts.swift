import Foundation
import os

/// Points-of-Interest intervals around the stage's per-frame work (US-316, brief D9), so an
/// Instruments trace can attribute a slow frame to planning, the thread or the dots.
///
/// **Signposts measure CPU work only**: building the `Path`s and submitting them. Scan
/// conversion happens later, partly on the GPU, and only the Animation Hitches trace sees it —
/// which is why the dot-versus-thread question is settled by the live controls, not by these.
///
/// In a build without `DEBUG` the interval is a plain call, so shipping frames carry nothing.
enum StageSignposts {
    #if DEBUG
        private static let signposter = OSSignposter(
            subsystem: "org.catrobat.embroiderydesigner", category: .pointsOfInterest
        )

        /// Whether a launch asks for the per-frame intervals (`-US316FrameSignposts`). Off by
        /// default: about 21 a frame at 60 Hz overflowed the recorder's signpost buffer in a
        /// 2-minute hand run, which then kept only its last 0.7 s of intervals and lost its
        /// `capture` window's Begin (2026-10-29). D6's runs need only the window and the result;
        /// D9's attribution runs turn these on.
        static func recordsFrames(arguments: [String]) -> Bool {
            arguments.contains("-US316FrameSignposts")
        }

        /// Read once: `ProcessInfo.arguments` cannot change, and this is asked on every frame.
        private static let framesEnabled = recordsFrames(arguments: ProcessInfo.processInfo.arguments)

        /// A per-frame interval, recorded only when the launch asked for them.
        static func interval<Result>(_ name: StaticString, _ body: () -> Result) -> Result {
            guard framesEnabled else { return body() }
            let state = signposter.beginInterval(name)
            defer { signposter.endInterval(name, state) }
            return body()
        }

        /// A long interval with no closure, for the capture window itself.
        static func begin(_ name: StaticString) -> OSSignpostIntervalState {
            signposter.beginInterval(name)
        }

        static func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
            signposter.endInterval(name, state)
        }

        /// A Points-of-Interest event carrying a capture's result line, so a run recorded under
        /// `xctrace` holds its own line beside its hitches (the Hitches template records no
        /// unified log; the `os-log` table came back empty).
        static func result(_ line: String) {
            signposter.emitEvent("result", "\(line, privacy: .public)")
        }
    #else
        @inline(__always)
        static func interval<Result>(_: StaticString, _ body: () -> Result) -> Result {
            body()
        }
    #endif
}
