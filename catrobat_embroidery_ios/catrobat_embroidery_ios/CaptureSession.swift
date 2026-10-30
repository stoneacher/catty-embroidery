#if DEBUG
    import Foundation
    import os
    import Samples
    import StagePreview
    import UIKit

    /// US-316's unattended capture, executing a `CaptureSequence` against the running app
    /// (brief D4, D5).
    ///
    /// **Exists only when the process was launched with `-US316Capture`**: `current` is `nil`
    /// otherwise, so the stage's coordinator never registers, no display link is added and an
    /// ordinary debug run — or a test process — is untouched.
    ///
    /// It steps on its own display link and passes `targetTimestamp` as the sequence's clock,
    /// so the gesture is placed where it should be when the frame is shown. That link is main-
    /// thread work a finger does not add; D4 records it, and the calibration (D7) is what
    /// judges it. Results go to the console as one line (`FrameCaptureReport`), flushed, and
    /// the process exits, so `devicectl … launch --console` and `xctrace --launch` both return
    /// with no one at the phone.
    @MainActor
    final class CaptureSession: NSObject {
        static let current = make(arguments: ProcessInfo.processInfo.arguments)

        static func make(arguments: [String]) -> CaptureSession? {
            guard let scenario = CaptureScenario.parse(arguments), !scenario.isByHand else { return nil }
            return CaptureSession(scenario: scenario)
        }

        private let scenario: CaptureScenario
        private var sequence: CaptureSequence
        private weak var model: AppModel?
        private weak var coordinator: StageManipulationCatcher.Coordinator?
        private var link: CADisplayLink?
        private var driver: GestureDriver?
        private let recorder = FrameTimeRecorder()
        private var thermalAtStart = ProcessInfo.ThermalState.nominal
        /// `nil` until a gesture begins: `A0-run` never begins one, and reports `n/a`.
        private var scaleAtStart: Double?
        private var settledAtStart: StageDrawRecord?
        private var captureInterval: OSSignpostIntervalState?
        private var exitCode: Int32 = 0

        private init(scenario: CaptureScenario) {
            self.scenario = scenario
            sequence = CaptureSequence(scenario: scenario)
        }

        /// The window's model is ready: select the fixture, show the stage, and start stepping.
        func attach(model: AppModel) {
            guard self.model == nil else { return }
            self.model = model
            // A capture outlasts auto-lock, and a locked phone records nothing.
            UIApplication.shared.isIdleTimerDisabled = true
            // A run interrupted by a call or Control Center must read INTERRUPTED, not FAIL with
            // the gap as one frame (`swift-code-reviewer`, slices 2–4).
            let center = NotificationCenter.default
            center.addObserver(
                self, selector: #selector(resigned), name: UIApplication.willResignActiveNotification, object: nil
            )
            center.addObserver(
                self, selector: #selector(resumed), name: UIApplication.didBecomeActiveNotification, object: nil
            )
            perform(sequence.launched(at: CACurrentMediaTime()))
            let link = CADisplayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        /// The stage's coordinator exists: the stage is on screen.
        func register(_ coordinator: StageManipulationCatcher.Coordinator) {
            self.coordinator = coordinator
            perform(sequence.stageAppeared())
        }

        @objc private func resigned() {
            recorder.noteSuspended()
        }

        @objc private func resumed() {
            recorder.noteResumed()
        }

        @objc private func step(_ link: CADisplayLink) {
            // **The recorder is fed from this link, before this frame's actions**, so a draw an
            // action causes is attributed by the next callback in a fixed order, and there is
            // no second display link on the main thread (D4's added cost; `swift-code-reviewer`).
            recorder.record(timestamp: link.timestamp, frameDuration: link.targetTimestamp - link.timestamp)
            let now = link.targetTimestamp
            if case .finished = model?.runner.run.state {
                perform(sequence.runFinished(at: now))
            }
            perform(sequence.tick(at: now))
        }

        private func perform(_ actions: [CaptureSequence.Action]) {
            for action in actions {
                perform(action)
            }
        }

        private func perform(_ action: CaptureSequence.Action) {
            switch action {
            case let .selectAndShowStage(id):
                guard let model, let sample = model.samples.first(where: { $0.id == id }) else { return }
                model.select(sample)
                // On compact the stage is pushed from the script; on regular this is ignored.
                model.path = [.script, .stage]
            case .play:
                model?.play()
            case let .zoom(fraction):
                makeDriver()?.zoom(to: fraction)
            case .startRecording:
                thermalAtStart = ProcessInfo.processInfo.thermalState
                // The settled frame US-322's fields describe is the last one before recording:
                // read it now, before the gesture makes every frame live.
                settledAtStart = StageDrawCounter.lastSettled
                captureInterval = StageSignposts.begin("capture")
                recorder.start(ownsLink: false)
            case .beginGesture:
                scaleAtStart = currentScale
                guard let driver = makeDriver() else {
                    // The stage went away after it appeared: recording a stage nobody moves
                    // would be a capture of nothing.
                    perform(sequence.abandon(in: "noCoordinator"))
                    return
                }
                self.driver = driver
                driver.begin()
            case let .advanceGesture(seconds):
                driver?.advance(to: seconds)
            case .stopRecording:
                recorder.stop()
                if scenario.condition == .animating {
                    // `A0-run` starts recording before the stage has drawn a settled frame, so
                    // the record worth reporting is the run's last one: whether the raster was
                    // composited during the window it measured (PR #84 review).
                    settledAtStart = StageDrawCounter.lastSettled
                }
                if let captureInterval {
                    StageSignposts.end("capture", captureInterval)
                }
            case .endGesture:
                driver?.end()
            case .report:
                report()
            case let .abort(stuck):
                emit("US316 condition=\(scenario.condition.rawValue) ABORTED \(stuck)")
                exitCode = 1
            case .exit:
                link?.invalidate()
                exit(exitCode)
            }
        }

        private func makeDriver() -> GestureDriver? {
            guard let coordinator else { return nil }
            return GestureDriver(
                coordinator: coordinator,
                script: GestureScript(kind: scenario.condition.gesture),
                viewport: coordinator.snapshot.viewport
            )
        }

        /// The committed scale the gesture starts from — after condition C's zoom, the zoomed
        /// one.
        private var currentScale: Double? {
            guard let model, let coordinator else { return nil }
            let snapshot = coordinator.snapshot
            return model.interaction.transform(
                with: nil, fitting: snapshot.fitted, in: snapshot.viewport
            ).scale
        }

        private func report() {
            let context = FrameCaptureReport.Context(
                condition: scenario.condition,
                thermalAtStart: thermalAtStart,
                thermalAtEnd: ProcessInfo.processInfo.thermalState,
                scale: scaleAtStart,
                threadWidth: scaleAtStart.map { StitchDrawMetrics.threadWidth(atScale: $0) },
                canvasSize: settledAtStart?.canvasSize,
                viewport: settledAtStart?.viewportSize,
                raster: settledAtStart?.raster ?? .unobserved
            )
            emit(FrameCaptureReport(recorder: recorder).consoleLine(context))
        }

        /// One result line, to the console **and** as a Points-of-Interest event, so a run under
        /// `xctrace` carries its own line inside the trace beside its hitches.
        private func emit(_ line: String) {
            print(line)
            // `stdout` is block-buffered when it is not a terminal, and `exit` follows.
            fflush(stdout)
            StageSignposts.result(line)
            // The trace lost a result event once; the file is the copy that does not depend on it.
            try? CaptureResultLog.append(line)
        }
    }
#endif
