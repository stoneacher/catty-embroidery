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
    /// **This, not `Task.isCancelled`, is what makes a stale update impossible.** Cancelling
    /// the consumer does not stop buffered elements from arriving (measured), and
    /// `PreviewRunState`'s "only a running run accepts updates" guard is not sufficient
    /// either: `begin()` A, `reset()`, `begin()` B leaves B `.running`, so A's late frames
    /// would be accepted (Codex round 1 constructed exactly that). A generation captured by
    /// the consumer closure and compared on delivery is what closes it, whatever the
    /// cancellation timing — the same device `SampleSelection.generation` uses to tell two
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
                // The identity check, which is the one that actually holds: see `generation`.
                guard let self, generation == mine else {
                    return
                }
                apply(update)
            }
        }
    }

    /// Asks the run to stop, keeping the stitches made so far and the export model.
    ///
    /// **Cancels the producer only.** The consumer keeps draining until the stream finishes
    /// on its own — **one or two** elements later, since the producer observes cancellation
    /// between frames and a `stop()` landing inside a frame yields that frame's ordinary
    /// update before the terminal.
    ///
    /// Cancelling the consumer here — the obvious reading of "stop the run" — would leave the
    /// interpreter running to its natural end or the stitch cap and produce no
    /// `.stoppedByUser` terminal at all, because the producer is the only task that observes
    /// cancellation. That is the Catty `Stage.stopProject()` failure reproduced: the design
    /// survives, the export model does not.
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
        session?.stop()
        session = nil
        consumer?.cancel()
        consumer = nil
    }

    /// The single mutation per batch.
    func apply(_ update: RunUpdate) {
        run.apply(update)
    }
}
