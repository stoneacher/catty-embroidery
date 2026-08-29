// `EmbroideryEngine` arrives with US-308: `onRunTerminated` hands the export model out, and
// naming its type is the whole of this file's contact with the engine.
import EmbroideryEngine
import Interpreter
import Observation
import ProgramModel
import StagePreview

/// The app's run: it owns the driver, consumes its updates on the main actor, and
/// holds the one piece of state the stage renders from.
///
/// **Exactly one observed stored property, and exactly one method that mutates it.**
/// That is the story's "exactly one observable mutation per batch" criterion made
/// structural rather than disciplinary: a per-stitch fold is not reachable from
/// `apply(_:)` without adding a second statement, and there is no second observed
/// property for a batch to touch. Everything that could be got wrong about the fold
/// — the transitions, the append, the export capture, the settling watermark — lives
/// in `PreviewRunState`, in the package, under `swift test`.
///
/// **Owned by `AppModel`, never `@State` in a view.** ADR-023 records that
/// `RootView` swaps one navigation container for another on a horizontal size-class
/// change and tears down whatever the abandoned container owned. A run held in a
/// view's `@State` would therefore be cancelled — and a finished design lost — by an
/// iPad window resize, which is a fresh instance of exactly the hazard US-304 was
/// written to fix.
@MainActor
@Observable
final class RunViewModel {
    /// The only observed stored property. See the type's doc comment.
    private(set) var run = PreviewRunState()

    @ObservationIgnored private let driver: InterpreterDriver

    /// The producer. `stop()` cancels **this** and nothing else.
    @ObservationIgnored private var session: RunSession?

    /// The consumer. Cancelled only when a run is discarded, never by `stop()` — the
    /// producer is the only task that can *decide* to stop, because it is what observes
    /// cancellation and emits the terminal update carrying the export model.
    @ObservationIgnored private var consumer: Task<Void, Never>?

    /// Which run a delivered update belongs to.
    ///
    /// **Defence in depth, and deliberately labelled as such.** Two earlier versions of this
    /// comment claimed generation was *the* thing preventing stale updates; it is not, and
    /// Codex rounds 2 and 3 both had to say so. In the code as it stands the `Task.isCancelled`
    /// check below is what closes the case, because every generation change is coupled to a
    /// `discard()` that cancels the old consumer, and there is no suspension point between that
    /// check and `apply`.
    ///
    /// What the generation adds is independence from that coupling: it keeps stale frames out
    /// if a suspension is ever introduced between the check and the apply, or if a future path
    /// bumps the generation without cancelling. No test through the public API can distinguish
    /// the two today — confirmed in round 3 — so this says so rather than implying a test
    /// proves it. The device is the one `SampleSelection.generation` uses to tell two
    /// selections of the same design apart.
    @ObservationIgnored private var generation = 0

    /// Injectable so tests supply immediate or gated pacing. Defaults to the display
    /// pacing, whose interval is derived from the same number as
    /// `InterpreterClock.tickDelta` — see `AppRunClock`.
    init(driver: InterpreterDriver = InterpreterDriver(pacing: AppRunClock.pacing)) {
        self.driver = driver
    }

    /// Starts `program` from the beginning.
    ///
    /// A fresh `Interpreter` per play, which is the whole of "reset is one assignment":
    /// the interpreter is a `Sendable` value type, so starting over is constructing one,
    /// not unpicking an object graph.
    func play(_ program: Program) {
        discard()
        run.begin()

        generation += 1
        let mine = generation

        let session = driver.start(Interpreter(program: program, clock: AppRunClock.preview))
        self.session = session

        // A plain `Task {}`, deliberately — the opposite of the driver's producer. This
        // one *should* inherit `@MainActor`, because its whole job is to mutate observed
        // state, and hopping actors per batch would serialise the run behind a queue.
        // The work it awaits happens off-actor inside the driver.
        consumer = Task { [weak self] in
            for await update in session.updates {
                // **A cancelled consumer keeps receiving buffered elements**, so this check
                // is required rather than belt-and-braces. Cancelling an `AsyncStream`
                // consumer marks the stream terminal but does **not** discard `pending`:
                // measured, a consumer cancelled before it ever ran still received all five
                // buffered elements, and `next()` in a cancelled task with one element
                // buffered returned the element rather than `nil`.
                //
                // Without this, an orphaned consumer from a discarded run applied its
                // buffered frames into the run that replaced it — measured at 5 001 stitches
                // and a `.stitchLimitReached` state arriving *after* a `reset()`, and a
                // buffered terminal published the discarded design's export model, which is
                // US-308's input (`swift-code-reviewer`). Reachable by picking a new sample
                // while a run is in flight.
                //
                // `PreviewRunState.apply` additionally refuses updates outside a running
                // run, which closes the reset-then-late-frame case. It is **not** sufficient
                // on its own — `begin()` A, `reset()`, `begin()` B leaves B `.running` — which
                // is what the generation check below is for.
                if Task.isCancelled {
                    return
                }
                // Defence in depth rather than the load-bearing check — see `generation`.
                guard let self, generation == mine else {
                    return
                }
                apply(update)
            }
        }
    }

    /// Asks the run to stop, keeping the stitches made so far and the export model.
    ///
    /// **Cancels the producer only.** The consumer keeps draining until the stream finishes on
    /// its own — usually one element later, occasionally two. A stop landing inside a frame
    /// still costs only one, because the driver re-checks cancellation after the frame and the
    /// frame's stitches ride out on the terminal itself.
    ///
    /// Cancelling the consumer here — the obvious reading of "stop the run" — would stop the run
    /// too, through the stream's `onTermination`, but the terminal update would be yielded into a
    /// stream nobody is reading. The design survives; the completion reason and the export model
    /// do not. That is the Catty `Stage.stopProject()` failure reproduced.
    func stop() {
        session?.stop()
    }

    /// Discards the run entirely — for a new selection, not for a user stop.
    func reset() {
        discard()
        run.reset()
    }

    /// Nothing owns this object beyond the window today — `AppModel.runner` is a `let` living
    /// as long as the window — so this is unreachable rather than load-bearing. It is here
    /// because the ownership argument above would otherwise be incomplete: the consumer holds
    /// the session strongly, and the session owns the producer, so a `RunViewModel` released
    /// mid-run would leave the producer stepping the interpreter to `maxStitchesPerRun` —
    /// 200 000 stitches of work nobody will ever see (`swift-code-reviewer`). Cancelling the
    /// consumer is enough: that terminates the stream, and the stream's `onTermination`
    /// cancels the producer.
    deinit {
        consumer?.cancel()
    }

    /// Tears down both tasks. Unlike `stop()`, this *does* cancel the consumer: the run
    /// is being thrown away, so there is no terminal update worth waiting for.
    private func discard() {
        // Bumping the generation is what invalidates any update still in flight, including
        // after a plain `reset()` with no new `play()` behind it.
        generation += 1
        onRunDiscarded?()
        session?.stop()
        session = nil
        consumer?.cancel()
        consumer = nil
    }

    /// Called once, when a run reaches a terminal state, with the export model it produced.
    ///
    /// **A closure here rather than an `.onChange` in a view**, for the reason
    /// `AppModel.select(_:)` already records for the run reset and the fit: the view-side
    /// spellings re-fire when `RootView` rebuilds a navigation container after a horizontal
    /// size-class change (ADR-023), so an iPad window resize would re-prepare the export —
    /// writing a file again for a design nobody touched. The run is what knows it has
    /// terminated, so the run is what says so.
    ///
    /// `@ObservationIgnored` because it is a wiring detail, not state anyone renders.
    @ObservationIgnored var onRunTerminated: ((EmbroideryStream) -> Void)?

    /// Called whenever a run is thrown away — by `play()` starting a new one, or by
    /// `reset()`.
    ///
    /// **Hooked to `discard()` rather than to `play()`, and that is the whole point.** Round
    /// 1 of the cross-vendor review found Play Again leaving the previous export alive; the
    /// first fix put `exporter.discard()` in `AppModel.play()`, and round 2 pointed out that
    /// this left the invariant as a *convention*: `runner.play(program)` and `runner.reset()`
    /// are both reachable directly, and one of the story's own tests calls the former.
    /// `discard()` is the one chokepoint both paths already go through, so hanging it here
    /// makes "the prepared file goes when the design does" (ADR-026) hold however the run is
    /// discarded.
    @ObservationIgnored var onRunDiscarded: (() -> Void)?

    /// The single mutation per batch.
    func apply(_ update: RunUpdate) {
        // **Read before, not from the update.** `PreviewRunState.apply` refuses updates
        // outside a running run — the guard that keeps a discarded run's buffered frames out
        // — so an update carrying a terminal may be dropped entirely. Firing off
        // `update.termination` would announce a termination the state never accepted, and
        // hand US-308 the *discarded* design's export model: precisely the Critical the
        // in-loop review found in US-306, arriving through a new door.
        let wasRunning = run.state.isRunning
        run.apply(update)

        // **Exactly once, and this guard is defence in depth rather than the load-bearing
        // reason** — the same honest treatment `generation` above needed after two rounds of
        // review. What actually makes it once is the producer: every terminal path in
        // `InterpreterDriver` is `yield(terminal); return` with `finish()` in a `defer`, so
        // no update can follow a terminal through the app's own wiring. An in-loop review
        // deleted `wasRunning` entirely and the whole app suite stayed green, which is the
        // measurement behind that wording. What the guard adds is independence from the
        // driver's shape: a second terminal, or a stale one from a discarded run reaching a
        // `.finished` state, is rejected here rather than announced.
        if wasRunning, let model = run.exportModel {
            onRunTerminated?(model)
        }
    }
}
