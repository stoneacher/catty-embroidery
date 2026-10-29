#if DEBUG
    import Samples

    /// US-316's unattended capture as a pure sequence of actions (brief D5, D6).
    ///
    /// Launch → select the fixture, show the stage and play it through once (the pre-roll) →
    /// settle two seconds, once the stage's coordinator is there → [zoom, settle two more] →
    /// record while a gesture is held for the scenario's hold → stop recording → end the
    /// gesture → report → exit.
    ///
    /// **Played at launch, not when the stage appears**: the stage's gesture catcher, whose
    /// coordinator the driver needs, exists only once a design has drawn, so waiting for it
    /// before playing deadlocked (found by the slice's simulator dry run). The coordinator is
    /// instead a precondition for leaving the settle.
    ///
    /// **Recording starts a tenth of a second before the gesture begins**: the recorder's first
    /// callback only sets a baseline, so a draw before it is timed by nothing and the verdict
    /// reads `DRAWS NOT MEASURED` — which the first device captures did, with both in one tick
    /// and then one tick apart.
    ///
    /// **At the end the gesture stays down but stops moving for the same tenth of a second**, so
    /// nothing draws, and only then is recording stopped: the recorder times a draw by its
    /// *next* callback, so a draw after its last one is untimed — which stopping mid-motion did
    /// on device.
    ///
    /// **Recording stops before the gesture ends**: ending commits and re-bakes, and D6's run is
    /// a gesture never released inside the window. Times are seconds on one monotonic clock
    /// (the display link's), supplied by the caller, so the whole sequence is a value test.
    struct CaptureSequence {
        enum Action: Equatable {
            case selectAndShowStage(SampleID)
            case play
            case zoom(Double)
            case startRecording
            case beginGesture
            case advanceGesture(Double)
            case stopRecording
            case endGesture
            case report
            /// The run never reached recording; the payload names the phase it was stuck in.
            case abort(String)
            case exit
        }

        private enum Phase: Equatable {
            case launching
            case running
            case settling(until: Double)
            case zoomSettling(until: Double)
            case arming(until: Double)
            case recording(since: Double)
            case stilling(until: Double)
            case done
        }

        /// How long the stage settles after the run, and again after a zoom, before recording.
        static let settleSeconds = 2.0

        /// How long recording runs before the gesture begins, and how long the gesture stays
        /// still before recording stops: six frames at 60 Hz. One tick was
        /// not enough on device — a newly added display link's first callback can come a frame
        /// late, and the draw in between was timed by nothing (`DRAWS NOT MEASURED (1)`).
        static let armingSeconds = 0.1

        private let scenario: CaptureScenario
        private var phase = Phase.launching
        private var hasStage = false
        private var launchedAt = 0.0

        /// How long a run may take to start recording before it is abandoned: the 50 001-stitch
        /// pre-roll takes about 17 s, so two minutes means something is stuck — a stage that never
        /// mounted, a run that never finished — and an unattended `xctrace` would otherwise wait
        /// forever (`swift-code-reviewer`, slices 2–4).
        static let deadlineSeconds = 120.0

        init(scenario: CaptureScenario) {
            self.scenario = scenario
        }

        var isDone: Bool {
            phase == .done
        }

        mutating func launched(at now: Double = 0) -> [Action] {
            guard phase == .launching else { return [] }
            launchedAt = now
            phase = .running
            return [.selectAndShowStage(scenario.condition.sample), .play]
        }

        /// The stage's coordinator exists, so a gesture can be driven. Starts nothing itself.
        mutating func stageAppeared() -> [Action] {
            hasStage = true
            return []
        }

        /// Taken once: the session reports a finished run on every tick while it stays
        /// finished, and only the first may start the settle.
        mutating func runFinished(at now: Double) -> [Action] {
            guard phase == .running else { return [] }
            phase = .settling(until: now + Self.settleSeconds)
            return []
        }

        /// The run is stuck before recording: abandon it with a line rather than hang.
        mutating func abandon(in stuck: String) -> [Action] {
            phase = .done
            return [.abort(stuck), .exit]
        }

        mutating func tick(at now: Double) -> [Action] {
            if now - launchedAt >= Self.deadlineSeconds {
                switch phase {
                case .launching: return abandon(in: "launching")
                case .running: return abandon(in: "running")
                case .settling: return abandon(in: "settling")
                case .zoomSettling: return abandon(in: "zoomSettling")
                case .arming, .recording, .stilling, .done: break
                }
            }
            switch phase {
            case let .settling(until) where now >= until && hasStage:
                if let fraction = scenario.condition.zoomRelativeToFit {
                    phase = .zoomSettling(until: now + Self.settleSeconds)
                    return [.zoom(fraction)]
                }
                phase = .arming(until: now + Self.armingSeconds)
                return [.startRecording]
            case let .zoomSettling(until) where now >= until:
                phase = .arming(until: now + Self.armingSeconds)
                return [.startRecording]
            case let .arming(until) where now >= until:
                // The recorder's first callback has set its baseline by now, so every draw of
                // the gesture lands in a timed interval.
                phase = .recording(since: now)
                return [.beginGesture]
            case let .recording(since):
                let elapsed = now - since
                guard elapsed >= scenario.holdSeconds else { return [.advanceGesture(elapsed)] }
                phase = .stilling(until: now + Self.armingSeconds)
                return []
            case let .stilling(until) where now >= until:
                phase = .done
                return [.stopRecording, .endGesture, .report, .exit]
            case .launching, .running, .settling, .zoomSettling, .arming, .stilling, .done:
                return []
            }
        }
    }
#endif
