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
            case exit
        }

        private enum Phase: Equatable {
            case launching
            case running
            case settling(until: Double)
            case zoomSettling(until: Double)
            case recording(since: Double)
            case done
        }

        /// How long the stage settles after the run, and again after a zoom, before recording.
        static let settleSeconds = 2.0

        private let scenario: CaptureScenario
        private var phase = Phase.launching
        private var hasStage = false

        init(scenario: CaptureScenario) {
            self.scenario = scenario
        }

        var isDone: Bool {
            phase == .done
        }

        mutating func launched() -> [Action] {
            guard phase == .launching else { return [] }
            phase = .running
            return [.selectAndShowStage(scenario.condition.sample), .play]
        }

        /// The stage's coordinator exists, so a gesture can be driven. Starts nothing itself.
        mutating func stageAppeared() -> [Action] {
            hasStage = true
            return []
        }

        mutating func runFinished(at now: Double) -> [Action] {
            guard phase == .running else { return [] }
            phase = .settling(until: now + Self.settleSeconds)
            return []
        }

        mutating func tick(at now: Double) -> [Action] {
            switch phase {
            case let .settling(until) where now >= until && hasStage:
                if let fraction = scenario.condition.zoomRelativeToFit {
                    phase = .zoomSettling(until: now + Self.settleSeconds)
                    return [.zoom(fraction)]
                }
                phase = .recording(since: now)
                return [.startRecording, .beginGesture]
            case let .zoomSettling(until) where now >= until:
                phase = .recording(since: now)
                return [.startRecording, .beginGesture]
            case let .recording(since):
                let elapsed = now - since
                guard elapsed >= scenario.holdSeconds else { return [.advanceGesture(elapsed)] }
                phase = .done
                return [.stopRecording, .endGesture, .report, .exit]
            case .launching, .running, .settling, .zoomSettling, .done:
                return []
            }
        }
    }
#endif
