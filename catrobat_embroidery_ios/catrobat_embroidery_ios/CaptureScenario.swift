#if DEBUG
    import Foundation
    import Samples

    /// What a frame-time capture draws while live, for US-316's renderer controls (brief D1).
    ///
    /// `none` is the shipping frame. The two controls each suppress one half of a live frame, so
    /// a capture can say whether the tail follows the dots or the thread. Settled frames are
    /// never affected.
    enum LiveDrawControl: Equatable {
        case none
        case noDots
        case noThread

        /// Which halves of a frame are drawn — the renderer's own type.
        typealias Layers = CanvasStitchStroke.Layers

        /// What a frame draws under this control: a live frame loses its suppressed half, a
        /// settled one is always whole.
        func layers(isLive: Bool) -> Layers {
            guard isLive else { return .all }
            switch self {
            case .none: return .all
            case .noDots: return Layers(thread: true, dots: false)
            case .noThread: return Layers(thread: false, dots: true)
            }
        }

        /// The control a launch asks for: its capture condition's, or none.
        static func from(arguments: [String]) -> LiveDrawControl {
            CaptureScenario.parse(arguments)?.condition.liveControl ?? .none
        }

        /// This process's control, read once: `ProcessInfo.arguments` cannot change, and the
        /// renderer asks on every frame.
        static let forProcess = from(arguments: ProcessInfo.processInfo.arguments)
    }

    /// One of US-316's capture conditions (brief D1), named by the token the launch argument
    /// carries.
    enum CaptureCondition: String, CaseIterable {
        /// A0: the shipping fixture, panned at fit — the baseline.
        case baseline = "A0"
        /// B: the overlap-density fixture at fit.
        case compact = "B"
        /// C: the baseline zoomed out, so it covers at most a tenth of its fitted area.
        case zoomedOut = "C"
        /// D: the baseline with the live dots suppressed.
        case noDots = "D"
        /// E: the baseline with the live thread suppressed.
        case noThread = "E"
        /// The supplementary mixed pinch-and-pan run on the baseline (D6).
        case baselineMixed = "A0-mixed"

        /// The design the run selects.
        var sample: SampleID {
            self == .compact ? .us316Compact : .us309Synthetic
        }

        var gesture: GestureScript.Kind {
            self == .baselineMixed ? .mixed : .pan
        }

        var liveControl: LiveDrawControl {
            switch self {
            case .noDots: .noDots
            case .noThread: .noThread
            case .baseline, .compact, .zoomedOut, .baselineMixed: .none
            }
        }

        /// The scale, as a fraction of the fit, the run zooms to before it records; `nil` to
        /// record at fit.
        ///
        /// 0.3, so the covered view area is 0.09 of the fitted one, inside D3's tenth. Below
        /// the 0.75 pt width floor the thread stops thinning, which is why the console line
        /// prints the scale and width actually used rather than this factor.
        var zoomRelativeToFit: Double? {
            self == .zoomedOut ? 0.3 : nil
        }
    }

    /// What one launch asks the app to capture: `-US316Capture <condition>`, and optionally
    /// `-US316Hold <seconds>`.
    ///
    /// **Parsed from an argument list, not from `ProcessInfo`**, so every rule is a value test.
    /// Without the argument it is `nil`, and then nothing registers with the driver.
    struct CaptureScenario: Equatable {
        static let captureFlag = "-US316Capture"
        static let holdFlag = "-US316Hold"

        /// ADR-043's bar is over a capture of **at least ten seconds**, and the recorded window is a
        /// little shorter than the hold: the recorder's first callback times nothing, so a 10 s hold
        /// records 9.9 s and reads `(short)` (the slice's simulator dry run). Half a second of margin
        /// makes every accepted hold quotable.
        static let minimumHoldSeconds = 10.5

        let condition: CaptureCondition

        /// How long the gesture is held while recording. 12 s by default (D6), so the capture
        /// clears the bar's 10 s with the settle margin to spare.
        let holdSeconds: Double

        static func parse(_ arguments: [String]) -> CaptureScenario? {
            guard let flag = arguments.firstIndex(of: captureFlag),
                  flag + 1 < arguments.count,
                  let condition = CaptureCondition(rawValue: arguments[flag + 1])
            else { return nil }

            var hold = 12.0
            if let holdFlagIndex = arguments.firstIndex(of: holdFlag) {
                guard holdFlagIndex + 1 < arguments.count,
                      let seconds = Double(arguments[holdFlagIndex + 1]),
                      seconds >= minimumHoldSeconds
                else { return nil }
                hold = seconds
            }
            return CaptureScenario(condition: condition, holdSeconds: hold)
        }
    }
#endif
