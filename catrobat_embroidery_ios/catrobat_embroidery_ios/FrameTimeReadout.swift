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
            guard let all = recorder.statistics else {
                return "US-309 frame times"
            }
            let verdict = FrameCaptureVerdict.of(
                all: all,
                drawn: recorder.drawnStatistics,
                totalDraws: recorder.drawCount ?? 0,
                unmeasuredDraws: recorder.unmeasuredDrawCount,
                wasInterrupted: recorder.wasInterrupted
            )
            let counts = "n=\(all.frameCount) drawn=\(recorder.drawnStatistics?.frameCount ?? 0)\(nominal)"
            let window = "\(seconds(all.totalMilliseconds)) s"
            // **The quantiles shown are the drawn frames', not every frame's**, because those
            // are the only ones the renderer had anything to do with. Falls back to the whole
            // capture when nothing was drawn, so the row is never blank — the `NO DRAWS`
            // label is what says not to read them.
            let quoted = recorder.drawnStatistics ?? all
            let quantiles = "med \(ms(quoted.median)) p95 \(ms(quoted.p95)) p99 \(ms(quoted.p99))"
            let worstFrame = "max \(ms(quoted.worst))@\(seconds(quoted.worstAtMilliseconds))s"
            return "\(counts) \(quantiles) \(worstFrame) · \(window) · \(verdict.label)"
        }

        /// The display's actual rate, or nothing if no callback has reported one.
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

        private func seconds(_ milliseconds: Double) -> String {
            String(format: "%.1f", milliseconds / 1_000)
        }

        /// Frame times to **three** decimals, and that is not fussiness.
        ///
        /// The bar is `p99 <= 16.67 ms` and a 60 Hz link's true period is 16.6667 ms, so a
        /// passing capture and a failing one differ in the **third** decimal. At one decimal
        /// both print `16.7`: the first device capture came back `med 16.7 p95 16.7 p99 16.7
        /// max 16.7 · FAIL` and the readout could not say whether that was a renderer miss or
        /// jitter a hundredth of a millisecond over the line. An instrument whose printed
        /// precision is coarser than the threshold it reports against cannot be read.
        ///
        /// Durations stay at one decimal — nobody needs microseconds on a capture window.
        private func ms(_ value: Double) -> String {
            String(format: "%.3f", value)
        }
    }
#endif
