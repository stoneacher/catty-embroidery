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
    /// **Nothing at all is shown per frame, and that is a measurement decision.** The caption used
    /// to count frames live, which made this row re-evaluate its body — two `String(format:)`
    /// calls and a `.regularMaterial` blur, composited over the canvas under measurement — once
    /// per displayed frame, on an otherwise static stage. The instrument was inside its own
    /// distribution, and a marginal capture would have sent the tester down ADR-029's fallback
    /// ladder after a cost the instrument introduced. While a capture runs this is a constant
    /// string; the ten-second window is timed by the tester and checked afterwards by
    /// `isLongEnoughToQuote`, which flags a short capture as `(short)`.
    ///
    /// Shown only for `SampleID.us309Synthetic`, so no shipping design's screenshot acquires a
    /// diagnostic overlay it did not have before this story.
    struct FrameTimeReadout: View {
        @State private var recorder = FrameTimeRecorder()
        @Environment(\.scenePhase) private var scenePhase

        var body: some View {
            HStack(spacing: 8) {
                Button(recorder.isRecording ? "Stop" : "Record") {
                    if recorder.isRecording {
                        recorder.stop()
                    } else {
                        recorder.start()
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
                // Constant while recording — no per-frame body evaluation. See the type comment.
                return "capturing… hold ≥ 10 s, then Stop"
            }
            guard let stats = recorder.statistics else {
                return "US-309 frame times"
            }
            return """
            n=\(stats.frameCount) med \(ms(stats.median)) p95 \(ms(stats.p95)) \
            p99 \(ms(stats.p99)) max \(ms(stats.worst)) · \(String(
                format: "%.1f",
                stats.totalMilliseconds / 1000
            )) s · \
            \(verdict(stats))
            """
        }

        /// `INTERRUPTED` outranks `PASS`/`FAIL`, because a capture the app was backgrounded
        /// during has measured a gap rather than a renderer, and the hand-off's instruction on a
        /// missed bar is to start tuning — the wrong destination for an artefact.
        private func verdict(_ stats: FrameTimeStatistics) -> String {
            if recorder.wasInterrupted {
                return "INTERRUPTED — discard and re-capture"
            }
            return "\(stats.meetsSixtyFps ? "PASS" : "FAIL")\(stats.isLongEnoughToQuote ? "" : " (short)")"
        }

        private func ms(_ value: Double) -> String {
            String(format: "%.1f", value)
        }
    }
#endif
