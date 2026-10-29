#if DEBUG
    import Foundation
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
            CaptureScenario.parse(arguments).map(CaptureSession.init)
        }

        private let scenario: CaptureScenario
        private var sequence: CaptureSequence
        private weak var model: AppModel?
        private weak var coordinator: StageManipulationCatcher.Coordinator?
        private var link: CADisplayLink?
        private var driver: GestureDriver?
        private let recorder = FrameTimeRecorder()
        private var thermalAtStart = ProcessInfo.ThermalState.nominal
        private var scaleAtStart = 1.0

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
            perform(sequence.launched())
            let link = CADisplayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        /// The stage's coordinator exists: the stage is on screen.
        func register(_ coordinator: StageManipulationCatcher.Coordinator) {
            self.coordinator = coordinator
            perform(sequence.stageAppeared())
        }

        @objc private func step(_ link: CADisplayLink) {
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
                recorder.start()
            case .beginGesture:
                scaleAtStart = currentScale ?? 1
                driver = makeDriver()
                driver?.begin()
            case let .advanceGesture(seconds):
                driver?.advance(to: seconds)
            case .stopRecording:
                recorder.stop()
            case .endGesture:
                driver?.end()
            case .report:
                report()
            case .exit:
                link?.invalidate()
                exit(0)
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
                threadWidth: StitchDrawMetrics.threadWidth(atScale: scaleAtStart),
                canvasSize: nil,
                viewport: nil,
                raster: .unobserved
            )
            print(FrameCaptureReport(recorder: recorder).consoleLine(context))
            // `stdout` is block-buffered when it is not a terminal, and `exit` follows.
            fflush(stdout)
        }
    }
#endif
