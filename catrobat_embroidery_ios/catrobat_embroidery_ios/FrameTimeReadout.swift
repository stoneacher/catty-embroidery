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
            guard let stats = recorder.statistics else {
                return "US-309 frame times"
            }
            let quantiles = "med \(ms(stats.median)) p95 \(ms(stats.p95)) p99 \(ms(stats.p99))"
            let worstFrame = "max \(ms(stats.worst))@\(seconds(stats.worstAtMilliseconds))s"
            let counts = "n=\(stats.frameCount) draws=\(recorder.drawCount ?? 0)\(nominal)"
            return "\(counts) \(quantiles) \(worstFrame) · \(seconds(stats.totalMilliseconds)) s · \(verdict(stats))"
        }

        /// The display's nominal rate, or nothing if the link never reported one.
        ///
        /// On screen because a 30 Hz link makes every interval ~33.3 ms and so fails both
        /// halves of the bar for reasons that have nothing to do with the renderer — Low
        /// Power Mode, a critical thermal state, or the "Limit Frame Rate" accessibility
        /// setting are each enough (Codex round 1, finding 3). Seeing `30Hz` beside a `FAIL`
        /// is the difference between checking the device and starting down the ladder.
        private var nominal: String {
            guard let interval = recorder.nominalFrameMilliseconds, interval > 0 else { return "" }
            return " \(Int((1_000 / interval).rounded()))Hz"
        }

        /// **`INTERRUPTED` and `NO DRAWS` both outrank `PASS`/`FAIL`**, because each means the
        /// capture measured something other than the renderer — and the hand-off's answer to
        /// a missed bar is to start tuning, the wrong destination for either artefact.
        ///
        /// `NO DRAWS` catches the deeper of the two. A display-link callback fires on every
        /// refresh whether or not SwiftUI redrew anything, so a settled, static stage can
        /// report a flawless 60 fps having asked the renderer for nothing at all: that
        /// capture describes the display's cadence, which was never in question, rather than
        /// ADR-009's claim, which is (Codex round 1, finding 1).
        ///
        /// **Two verdicts rather than one, and zero is tested separately from the ratio.**
        /// The first spelling was `draws < stats.frameCount / 10`, which is integer division:
        /// any capture under ten frames has a threshold of **0**, so `draws == 0` compared
        /// `0 < 0` and such a capture was scored `PASS`/`FAIL` — the guard switched itself off
        /// exactly where the evidence is thinnest. Zero draws is now its own case and needs no
        /// threshold. The ratio case is kept for a capture that *did* render but spent most of
        /// its frames idle, and it says so rather than claiming nothing was drawn: those frame
        /// times are still mostly the display's, so the tail cannot be read as the renderer's.
        /// `draws * 10 < frameCount` rather than a division, so nothing truncates.
        private func verdict(_ stats: FrameTimeStatistics) -> String {
            if recorder.wasInterrupted {
                return "INTERRUPTED — discard and re-capture"
            }
            if let draws = recorder.drawCount {
                if draws == 0 {
                    return "NO DRAWS — measures the display, not the renderer"
                }
                if draws * 10 < stats.frameCount {
                    return "MOSTLY IDLE — \(draws) draws in \(stats.frameCount) frames"
                }
            }
            let bar = stats.meetsSixtyFps ? "PASS" : "FAIL"
            return "\(bar)\(stats.isLongEnoughToQuote ? "" : " (short)")"
        }

        private func seconds(_ milliseconds: Double) -> String {
            String(format: "%.1f", milliseconds / 1_000)
        }

        private func ms(_ value: Double) -> String {
            String(format: "%.1f", value)
        }
    }
#endif
