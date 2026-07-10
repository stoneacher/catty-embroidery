import EmbroideryEngine
import Testing

@Suite("RunningStitch lifecycle")
struct RunningStitchTests {
    private func needle(_ x: Double, _ y: Double) -> NeedleUpdate {
        NeedleUpdate(position: StagePoint(x: x, y: y))
    }

    private func activatedRunningStitch(length: Double = 2) -> RunningStitch {
        var wrapper = RunningStitch()
        wrapper.activate(RunningStitchPattern(length: length, start: StagePoint(x: 0, y: 0)))
        return wrapper
    }

    @Test("activate installs the pattern and starts: update delegates")
    func activateDelegates() {
        var wrapper = activatedRunningStitch()
        #expect(wrapper.isRunning)
        #expect(wrapper.update(needle(10, 0)) == [
            StagePoint(x: 0, y: 0),
            StagePoint(x: 2, y: 0),
            StagePoint(x: 4, y: 0),
            StagePoint(x: 6, y: 0),
            StagePoint(x: 8, y: 0),
            StagePoint(x: 10, y: 0)
        ], "port of Catroid testActivateRunningStitch")
    }

    @Test("update before activate emits nothing")
    func updateBeforeActivate() {
        var wrapper = RunningStitch()
        #expect(!wrapper.isRunning)
        #expect(wrapper.update(needle(10, 0)).isEmpty)
    }

    @Test("resume before activate stays stopped")
    func resumeBeforeActivate() {
        // Port of Catroid testInvalidResumeRunningStitch: resume only takes
        // effect while a pattern is installed.
        var wrapper = RunningStitch()
        wrapper.resume()
        #expect(!wrapper.isRunning)
        #expect(wrapper.update(needle(10, 0)).isEmpty)
    }

    @Test("pause suppresses updates without touching pattern state")
    func pauseSuppressesUpdates() {
        var wrapper = activatedRunningStitch()
        wrapper.pause()
        #expect(!wrapper.isRunning)
        #expect(wrapper.update(needle(10, 0)).isEmpty, "port of Catroid testPauseRunningStitch")
    }

    @Test("pause then resume continues without drift")
    func resumeWithoutDrift() {
        // A paused-and-resumed wrapper must produce exactly what an
        // uninterrupted one produces (Catroid testResumeRunningStitch;
        // resume never re-anchors — that is the caller's setStartPosition).
        var paused = activatedRunningStitch()
        var control = activatedRunningStitch()

        #expect(paused.update(needle(2, 0)) == control.update(needle(2, 0)))
        paused.pause()
        paused.resume()
        #expect(paused.isRunning)
        #expect(paused.update(needle(4, 0)) == control.update(needle(4, 0)))
        #expect(paused.update(needle(4, 0)) == [StagePoint(x: 4, y: 0)])
    }

    @Test("stop clears the pattern: updates stay empty and resume cannot restart")
    func stopClearsPattern() {
        var wrapper = activatedRunningStitch()
        wrapper.stop()
        #expect(!wrapper.isRunning)
        #expect(wrapper.update(needle(10, 0)).isEmpty, "port of Catroid testDeactivateRunningStitch")

        wrapper.resume()
        #expect(!wrapper.isRunning, "resume after stop has no pattern to resume")
        #expect(wrapper.update(needle(20, 0)).isEmpty)
    }

    @Test("setStartPosition before activate is a harmless no-op")
    func setStartBeforeActivate() {
        // Port of Catroid testInvalidSetStartCoordinates.
        var wrapper = RunningStitch()
        wrapper.setStartPosition(StagePoint(x: 1, y: 2))
        #expect(wrapper.update(needle(10, 0)).isEmpty)
    }

    @Test("setStartPosition after activate delegates to the pattern")
    func setStartDelegates() {
        // Wrapper-level port of Catroid testSetStartCoordinates, asserting
        // the re-anchored coordinates instead of a mock call count.
        var wrapper = RunningStitch()
        wrapper.activate(RunningStitchPattern(length: 10, start: StagePoint(x: 0, y: 0)))
        wrapper.setStartPosition(StagePoint(x: 20, y: 20))
        #expect(wrapper.update(needle(0, 0)) == [
            StagePoint(x: 20, y: 20),
            StagePoint(x: 13, y: 13),
            StagePoint(x: 6, y: 6)
        ])
    }
}
