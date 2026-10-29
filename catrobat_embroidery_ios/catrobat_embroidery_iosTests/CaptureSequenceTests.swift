@testable import catrobat_embroidery_ios
import Samples
import Testing

/// US-316's unattended capture, as a pure sequence (brief D5, D6): select the fixture and show
/// the stage, play it through once, settle, optionally zoom and settle again, then record a
/// held gesture, stop, end the gesture, report and exit.
struct CaptureSequenceTests {
    private static func scenario(_ condition: CaptureCondition, hold: Double = 12) -> CaptureScenario {
        CaptureScenario(condition: condition, holdSeconds: hold)
    }

    /// Runs the sequence through a fixed timeline and returns every action in order.
    private static func run(_ scenario: CaptureScenario) -> [CaptureSequence.Action] {
        var sequence = CaptureSequence(scenario: scenario)
        var actions = sequence.launched()
        actions += sequence.stageAppeared()
        actions += sequence.tick(at: 1)
        actions += sequence.runFinished(at: 20)
        var now = 20.0
        while !sequence.isDone, now < 100 {
            now += 0.5
            actions += sequence.tick(at: now)
        }
        return actions
    }

    @Test("a capture at fit: play, settle, record the held gesture, then stop before it ends")
    func atFit() {
        let actions = Self.run(Self.scenario(.compact))
        #expect(Array(actions.prefix(2)) == [.selectAndShowStage(.us316Compact), .play])
        let start = actions.firstIndex(of: .startRecording)
        #expect(start != nil)
        #expect(actions[(start ?? 0) + 1] == .beginGesture)
        #expect(!actions.contains {
            if case .zoom = $0 {
                true
            } else {
                false
            }
        })
        // **Recording stops before the gesture ends**: the end commits and re-bakes, and D6's
        // run is a gesture that is never released inside the window.
        #expect(Array(actions.suffix(4)) == [.stopRecording, .endGesture, .report, .exit])
    }

    /// Two seconds of settling after the run, before anything is recorded (D6).
    @Test("nothing is recorded until two seconds after the run finishes")
    func settlesFirst() {
        var sequence = CaptureSequence(scenario: Self.scenario(.baseline))
        _ = sequence.launched()
        _ = sequence.stageAppeared()
        _ = sequence.runFinished(at: 20)
        #expect(sequence.tick(at: 21.9).isEmpty)
        #expect(sequence.tick(at: 22) == [.startRecording, .beginGesture])
    }

    /// Condition C zooms once, then settles again so the re-bake is outside the window.
    @Test("the zoomed-out condition zooms, settles again, then records")
    func zoomsFirst() {
        var sequence = CaptureSequence(scenario: Self.scenario(.zoomedOut))
        _ = sequence.launched()
        _ = sequence.stageAppeared()
        _ = sequence.runFinished(at: 20)
        #expect(sequence.tick(at: 22) == [.zoom(0.3)])
        #expect(sequence.tick(at: 23.9).isEmpty)
        #expect(sequence.tick(at: 24) == [.startRecording, .beginGesture])
    }

    /// The gesture is advanced by the time since recording began, and the hold is the
    /// scenario's.
    @Test("the gesture advances by elapsed time and stops after the hold")
    func holds() {
        var sequence = CaptureSequence(scenario: Self.scenario(.baseline, hold: 10))
        _ = sequence.launched()
        _ = sequence.stageAppeared()
        _ = sequence.runFinished(at: 20)
        _ = sequence.tick(at: 22)
        #expect(sequence.tick(at: 22.5) == [.advanceGesture(0.5)])
        #expect(sequence.tick(at: 31.75) == [.advanceGesture(9.75)])
        #expect(sequence.tick(at: 32) == [.stopRecording, .endGesture, .report, .exit])
        #expect(sequence.isDone)
        #expect(sequence.tick(at: 40).isEmpty)
    }

    /// The run is played straight after selecting, **not** on the stage's appearance: the
    /// stage's gesture catcher exists only once a design has drawn, so waiting for it before
    /// playing deadlocks (found by the slice's simulator dry run). Played once only.
    @Test("the run is played once, at launch")
    func playsOnce() {
        var sequence = CaptureSequence(scenario: Self.scenario(.baseline))
        #expect(sequence.launched() == [.selectAndShowStage(.us309Synthetic), .play])
        #expect(sequence.launched().isEmpty)
        #expect(sequence.stageAppeared().isEmpty)
    }

    /// Recording needs the stage's coordinator to drive: without it a capture would record a
    /// stage nobody moves. So the settle waits for the stage as well as the clock.
    @Test("nothing is recorded until the stage is there")
    func waitsForTheStage() {
        var sequence = CaptureSequence(scenario: Self.scenario(.baseline))
        _ = sequence.launched()
        _ = sequence.runFinished(at: 20)
        #expect(sequence.tick(at: 30).isEmpty)
        _ = sequence.stageAppeared()
        #expect(sequence.tick(at: 30.5) == [.startRecording, .beginGesture])
    }

    @Test("ticks before the run finishes do nothing")
    func waitsForTheRun() {
        var sequence = CaptureSequence(scenario: Self.scenario(.baseline))
        _ = sequence.launched()
        _ = sequence.stageAppeared()
        #expect(sequence.tick(at: 100).isEmpty)
    }

    /// Without the launch argument there is no session, so nothing ever registers with a
    /// driver and the parallel suites never touch one.
    @Test("no argument, no session")
    @MainActor
    func noSessionWithoutArgument() {
        #expect(CaptureSession.make(arguments: ["app"]) == nil)
        #expect(CaptureSession.make(arguments: ["app", "-US316Capture", "B"]) != nil)
    }
}
