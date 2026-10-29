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

        static func interval<Result>(_ name: StaticString, _ body: () -> Result) -> Result {
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
    #else
        @inline(__always)
        static func interval<Result>(_: StaticString, _ body: () -> Result) -> Result {
            body()
        }
    #endif
}
