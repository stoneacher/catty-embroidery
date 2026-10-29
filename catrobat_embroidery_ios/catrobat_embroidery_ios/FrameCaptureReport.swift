#if DEBUG
    import CoreGraphics
    import Foundation

    /// What a finished frame-time capture says, as text (US-316, brief D5).
    ///
    /// **One formatter for the capsule and the console**, so an unattended device capture prints
    /// exactly the text a screenshot of the capsule would show. The formatting moved here from
    /// `FrameTimeReadout` unchanged. The reasons for each field are in `FrameTimeRecorder`'s
    /// property docs (`drawnStatistics`, `drawCount`, `commitCount`, `nominalFrameMilliseconds`)
    /// and in `FrameCaptureVerdict`.
    struct FrameCaptureReport {
        let all: FrameTimeStatistics?
        let drawn: FrameTimeStatistics?
        let totalDraws: Int
        let unmeasuredDraws: Int
        let wasInterrupted: Bool
        let commits: Int
        let nominalFrameMilliseconds: Double?

        /// What the run was, beyond its frame times: everything the console line adds.
        struct Context {
            let condition: CaptureCondition
            let thermalAtStart: ProcessInfo.ThermalState
            let thermalAtEnd: ProcessInfo.ThermalState
            /// The stage scale the gesture began at, and the thread width it drew.
            let scale: Double
            let threadWidth: Double
            /// The last settled frame's `Canvas` size and viewport, and whether it composited
            /// the raster (US-322); `nil` or `.unobserved` when nothing recorded them.
            let canvasSize: CGSize?
            let viewport: CGSize?
            let raster: RasterObservation
        }

        /// Whether the last settled frame composited the baked raster — three cases rather
        /// than an optional `Bool`, so "not observed" can never read as "no".
        enum RasterObservation {
            case composited
            case notComposited
            case unobserved
        }

        var verdict: FrameCaptureVerdict {
            .of(
                all: all,
                drawn: drawn,
                totalDraws: totalDraws,
                unmeasuredDraws: unmeasuredDraws,
                wasInterrupted: wasInterrupted
            )
        }

        /// The capsule's text, or `nil` before any capture.
        var caption: String? {
            guard let all else { return nil }
            // `commits=` rides beside `drawn=` rather than inside the verdict: a capture is
            // not better or worse for containing gesture-ends, but the two numbers together
            // are what separate a per-frame cost from a per-commit tail (ADR-029, US-313b).
            let counts = "n=\(all.frameCount) drawn=\(drawn?.frameCount ?? 0)"
                + " commits=\(commits)\(nominal)"
            let window = "\(Self.seconds(all.totalMilliseconds)) s"
            // **The quantiles shown are the drawn frames', not every frame's**, because those
            // are the only ones the renderer had anything to do with. Falls back to the whole
            // capture when nothing was drawn, so the row is never blank — the `NO DRAWS`
            // label is what says not to read them.
            let quoted = drawn ?? all
            let quantiles = "med \(Self.ms(quoted.median)) p95 \(Self.ms(quoted.p95)) p99 \(Self.ms(quoted.p99))"
            let worstFrame = "max \(Self.ms(quoted.worst))@\(Self.seconds(quoted.worstAtMilliseconds))s"
            return "\(counts) \(quantiles) \(worstFrame) · \(window) · \(verdict.label)"
        }

        /// One line for the console: `US316`, the condition, the caption, every **drawn** frame
        /// over 33.3 ms, and the run's conditions.
        ///
        /// Only drawn frames are listed, for the reason the quantiles are the drawn frames': a
        /// slow interval in which the canvas did not draw is the display's, not the renderer's.
        func consoleLine(_ context: Context) -> String {
            let over = (drawn?.droppedFrames ?? [])
                .map { "\(String(format: "%.3f", $0.startMilliseconds / 1000))s:\(Self.ms($0.milliseconds))" }
                .joined(separator: ",")
            let raster = switch context.raster {
            case .composited: "yes"
            case .notComposited: "no"
            case .unobserved: "n/a"
            }
            return "US316 condition=\(context.condition.rawValue) \(caption ?? verdict.label)"
                + " | over33=[\(over)]"
                + " thermal=\(Self.name(context.thermalAtStart))>\(Self.name(context.thermalAtEnd))"
                + " scale=\(String(format: "%.3f", context.scale))"
                + " width=\(String(format: "%.3f", context.threadWidth))"
                + " canvas=\(Self.size(context.canvasSize)) viewport=\(Self.size(context.viewport))"
                + " raster=\(raster)"
        }

        /// A hand run's line (D7), emitted when the capsule's Stop is tapped: the driver's tag and
        /// caption, marked `hand`, under the launch's condition (`none` for a plain launch), with
        /// the thermal state at Record and at Stop so D6's discard rule applies to it too.
        func handLine(
            condition: CaptureCondition?,
            thermal: (start: ProcessInfo.ThermalState, end: ProcessInfo.ThermalState)
        ) -> String {
            "US316 condition=\(condition?.rawValue ?? "none") hand \(caption ?? verdict.label)"
                + " | thermal=\(Self.name(thermal.start))>\(Self.name(thermal.end))"
        }

        /// The display's actual rate, or nothing if no callback has reported one.
        ///
        /// On the row because a 30 Hz link makes every interval ~33.3 ms and so fails both
        /// halves of the bar for reasons that have nothing to do with the renderer (Codex
        /// round 1, finding 3; see `FrameTimeRecorder.nominalFrameMilliseconds`).
        private var nominal: String {
            guard let interval = nominalFrameMilliseconds, interval > 0 else { return "" }
            return " \(Int((1000 / interval).rounded()))Hz"
        }

        private static func seconds(_ milliseconds: Double) -> String {
            String(format: "%.1f", milliseconds / 1000)
        }

        /// Frame times to **three** decimals: a 60 Hz period is 16.6667 ms against a bar of
        /// 16.67, so a pass and a fail differ in the third decimal (see `FrameTimeReadout`'s
        /// history for the capture that could not be read at one).
        private static func ms(_ value: Double) -> String {
            String(format: "%.3f", value)
        }

        private static func size(_ size: CGSize?) -> String {
            guard let size else { return "n/a" }
            return String(format: "%.2fx%.2f", size.width, size.height)
        }

        private static func name(_ state: ProcessInfo.ThermalState) -> String {
            switch state {
            case .nominal: "nominal"
            case .fair: "fair"
            case .serious: "serious"
            case .critical: "critical"
            @unknown default: "unknown"
            }
        }
    }

    @MainActor
    extension FrameCaptureReport {
        /// The report of the recorder's last completed capture.
        init(recorder: FrameTimeRecorder) {
            self.init(
                all: recorder.statistics,
                drawn: recorder.drawnStatistics,
                totalDraws: recorder.drawCount ?? 0,
                unmeasuredDraws: recorder.unmeasuredDrawCount,
                wasInterrupted: recorder.wasInterrupted,
                commits: recorder.commitCount ?? 0,
                nominalFrameMilliseconds: recorder.nominalFrameMilliseconds
            )
        }
    }
#endif
