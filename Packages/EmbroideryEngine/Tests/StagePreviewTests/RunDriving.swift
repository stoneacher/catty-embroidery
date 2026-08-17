import Interpreter
import ProgramModel
import StagePreview

// Helpers for driving and draining a run. Free functions and free types, not suite
// members, matching `PreviewFixtures`' arrangement — and so that no one suite's
// `type_body_length` pays for them.

/// Everything a drained run produced, in one value the assertions can read.
struct DrainedRun {
    var updates: [RunUpdate] = []

    /// Every stitch the run delivered, in order — what the display list would hold.
    var stitches: [PreviewStitch] {
        updates.flatMap(\.batch.stitches)
    }

    /// The terminal, which a correct run always delivers exactly once.
    var termination: RunTermination? {
        updates.compactMap(\.termination).first
    }

    /// How many updates carried a terminal. Asserted to be exactly 1: a run that
    /// terminated twice, or that finished the stream without terminating, is a
    /// different bug from a run with the wrong reason and should not be able to
    /// masquerade as one.
    var terminalCount: Int {
        updates.count(where: { $0.termination != nil })
    }

    /// Stitches per update — the shape the frame-budget tests assert on. Trailing
    /// updates that carry no stitches are kept, because "the frame ended at the
    /// budget" is a claim about *which* frame the stitches landed in.
    var stitchCountsPerUpdate: [Int] {
        updates.map(\.batch.stitches.count)
    }
}

/// Consumes a session to completion.
///
/// **The consumer is never cancelled**, which is the whole reason `RunSession.stop()`
/// cancels only the producer: the producer is the only task that observes cancellation and
/// emits the terminal update carrying the export model, so cancelling the consumer would
/// leave the run going and produce no `.stoppedByUser` at all — the exact failure US-306's
/// export-after-stop criterion exists to prevent, and one that no producer-side test could
/// see. (Note that cancelling a consumer does *not* stop buffered elements arriving; that
/// premise was retracted after being measured. See `RunViewModel.generation`.)
func drain(_ session: RunSession) async -> DrainedRun {
    var drained = DrainedRun()
    for await update in session.updates {
        drained.updates.append(update)
    }
    return drained
}

/// Runs a program to completion through the driver at immediate pacing.
func driveToCompletion(
    _ program: Program, budget: RunBudget = .display
) async -> DrainedRun {
    let driver = InterpreterDriver(pacing: ImmediateRunPacing(), budget: budget)
    return await drain(driver.start(interpreter(program)))
}

/// How many `.stitch` events a program emits, derived independently of the driver.
///
/// Derived here rather than taken from US-301's harness because
/// `SampleRun`/`SampleRunHarness` live in `SamplesTests` and **SwiftPM forbids a
/// test target depending on another test target** — the same constraint that forced
/// US-301 ahead of US-302 in the milestone order. So the count is recomputed from
/// the interpreter directly, the way `DisplayVersusExportModelTests` already does,
/// and the two samples' figures are additionally pinned as literals so a drift names
/// itself rather than moving both sides of an equation at once.
func stitchEventCount(of program: Program) -> Int {
    var subject = interpreter(program)
    return tickBatches(&subject)
        .flatMap(\.self)
        .count { event in
            if case .stitch = event {
                return true
            }
            return false
        }
}

/// Pacing a test drives frame by frame.
///
/// **Required, not a convenience.** Under `ImmediateRunPacing` the producer races
/// ahead of the consumer, so a mid-run `stop()` is a race: for a terminating program
/// the run can finish naturally first and the completion reason comes back
/// `.programFinished` — a stop test that is green for the wrong reason, and flaky for
/// the right one. With this, the test grants exactly as many frames as it means to
/// before stopping.
///
/// An `actor` because the driver's detached producer and the test body both touch it.
///
/// Note that `withCheckedContinuation` is **not** cancellation-aware, which is
/// deliberate here: after `stop()` the producer stays parked in the gate until the
/// test grants one more frame, so the test controls exactly when the cancellation is
/// observed instead of racing it.
actor GatedRunPacing: RunPacing {
    private var credits = 0
    private var waiting: CheckedContinuation<Void, Never>?

    /// Lets one more frame be produced.
    func grant() {
        if let continuation = waiting {
            waiting = nil
            continuation.resume()
        } else {
            credits += 1
        }
    }

    nonisolated func waitForNextFrame() async {
        await gate()
    }

    private func gate() async {
        if credits > 0 {
            credits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiting = continuation
        }
    }
}
