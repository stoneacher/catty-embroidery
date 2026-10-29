#if DEBUG
    import SwiftUI

    /// US-309's readout: start a capture, stop it, read the four numbers off the screen.
    ///
    /// **On screen rather than in a log, because the measurement happens on a device.** A capture
    /// taken on a phone has to be readable without a console attached, and a screenshot of this
    /// row is the artefact that goes into the thesis beside the frame it describes. The numbers
    /// are shown only after `stop()`, so what is read is a settled result rather than four values
    /// moving while they are being read.
    ///
    /// **The quantiles are over the frames in which the canvas actually drew.** A display-link
    /// callback fires on every refresh whether or not SwiftUI drew anything, and the measured
    /// captures show the canvas drawing on a small minority of refreshes even mid-run — 251
    /// draws in 2 123 frames — so a p99 over *all* frames is mostly a p99 of frames in which
    /// nothing happened, and it flatters the renderer by exactly the idle fraction. `drawn=`
    /// is on the row beside `n=` so the two can never be confused, and a capture with no
    /// drawn frame at all is labelled rather than scored (`FrameCaptureVerdict`).
    ///
    /// **Nothing at all is shown per frame, and that is a measurement decision.** The caption used
    /// to count frames live, which made this row re-evaluate its body — two `String(format:)`
    /// calls and a `.regularMaterial` blur, composited over the canvas under measurement — once
    /// per displayed frame, on an otherwise static stage. The instrument was inside its own
    /// distribution, and a marginal capture would have sent the tester down ADR-029's fallback
    /// ladder after a cost the instrument introduced. While a capture runs this is a constant
    /// string; the ten-second window is timed by the tester and checked afterwards by
    /// `isLongEnoughToQuote`, which flags a short capture as `(short)`.
    ///
    /// Shown only for the measurement fixtures (`SampleID.us309Synthetic`, and since US-316
    /// `us316Compact`), so no shipping design's screenshot acquires a diagnostic overlay it
    /// did not have before this story.
    struct FrameTimeReadout: View {
        /// Whether this process was launched with `-US310FrameTimes`, which shows the readout for
        /// **every** design rather than only for the measurement fixtures.
        ///
        /// US-310's premise check needs a mid-gesture capture at a *small* stitch count, and there
        /// was no instrumented small design to take one on: the fixture this readout was then
        /// gated to is fixed at `us309SyntheticStitchCount` (50 001) with no smaller variant (as
        /// is US-316's compact fixture, added since). One
        /// count cannot separate a cost proportional to the primitive count from a fixed per-frame
        /// cost — two counts on one instrument can.
        ///
        /// An argument rather than a widened condition, so US-309's reason for the narrow gate
        /// survives: an ordinary debug run does not pass the flag, so no shipping design's
        /// screenshot acquires a diagnostic overlay it did not have before.
        ///
        /// Read **once**, and stored: `ProcessInfo.arguments` cannot change while the process
        /// runs, and scanning it inside a `body` would put the instrument's own cost into every
        /// frame of the stage it measures — the mistake this file's type doc already records
        /// once, for the live frame counter.
        static let isForcedForEverySample = ProcessInfo.processInfo.arguments
            .contains("-US310FrameTimes")

        @State private var recorder = FrameTimeRecorder()
        @Environment(\.scenePhase) private var scenePhase

        var body: some View {
            HStack(spacing: 8) {
                Button(recorder.isRecording ? "Stop" : "Record") {
                    if recorder.isRecording {
                        recorder.stop()
                    } else {
                        // The scene's *state*, not a transition: a capture begun while the
                        // app is not active must know that from the outset. See
                        // `start(isActive:)`.
                        recorder.start(isActive: scenePhase == .active)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)

                Text(caption)
                    // Monospaced digits so the row does not reflow while a capture runs, which
                    // would make it unreadable at exactly the moment it is being watched.
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 8)
            // Not an accessibility element worth describing: it is a developer instrument that
            // does not exist in any build a user can install, and giving it a label would put it
            // into the VoiceOver order of the stage this story is also screenshotting.
            .accessibilityHidden(true)
            // **The only deterministic release path for the display link.** This row is inside a
            // `case .drawn` branch, so `runner.reset()` — tapping Back, or picking another design
            // — removes it while a capture may still be running. Without this the link went on
            // firing for the rest of the process and contaminated the next capture, which on a
            // borrowed device is an afternoon.
            .onDisappear { recorder.stop() }
            // Backgrounding mid-capture: the link stops delivering but timestamps do not stop
            // advancing, so the gap would arrive as one multi-second frame and fail both halves
            // of the bar for reasons that have nothing to do with the renderer.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    recorder.noteResumed()
                } else {
                    recorder.noteSuspended()
                }
            }
        }

        private var caption: String {
            if recorder.isRecording {
                // Constant while recording — no per-frame body evaluation. See the type doc.
                return "capturing… hold ≥ 10 s, then Stop"
            }
            // Formatted by `FrameCaptureReport`, which US-316's console line shares, so a
            // screenshot of this row and an unattended device capture say the same thing.
            return FrameCaptureReport(recorder: recorder).caption ?? "US-309 frame times"
        }
    }
#endif
