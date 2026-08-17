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

    /// The consumer. Cancelled only when a run is discarded, never by `stop()`:
    /// `AsyncStream.Iterator.next()` returns `nil` in a cancelled task, so cancelling
    /// the consumer would drop the terminal update that carries the export model.
    @ObservationIgnored private var consumer: Task<Void, Never>?

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
                // `PreviewRunState.apply` additionally refuses updates unless the run is
                // `.running`, which makes the corruption unrepresentable; this stops the
                // wasted work rather than merely its effect.
                if Task.isCancelled {
                    return
                }
                self?.apply(update)
            }
        }
    }

    /// Asks the run to stop, keeping the stitches made so far and the export model.
    ///
    /// **Cancels the producer only.** The consumer keeps draining until the stream
    /// finishes on its own, one element later, because that last element is the terminal
    /// update carrying `assembledStream()`. Cancelling the consumer here — the obvious
    /// reading of "stop the run" — would make `AsyncStream.Iterator.next()` return `nil`
    /// and silently drop it, so the design would survive the stop but the export model
    /// would not. That is the Catty `Stage.stopProject()` failure, reproduced.
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
