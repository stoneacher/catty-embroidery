import EmbroideryEngine
import Interpreter

/// The needle's pose, with the object that moved it.
public struct PreviewNeedle: Hashable, Sendable {
    public var actor: ActorID
    public var update: NeedleUpdate

    public init(actor: ActorID, update: NeedleUpdate) {
        self.actor = actor
        self.update = update
    }
}

/// One tick's worth of interpreter output, folded into what the preview needs:
/// the stitches to append, the pose to draw the needle at, and whether the
/// program asked to be written out.
///
/// A **delta**, not an accumulator — the stitches are the ones this batch adds,
/// so US-306 appends them to the display list rather than replacing it. That is
/// what "batched before mutating observable state" means in practice.
///
/// Pure, so US-306's batching is tested here under `swift test` rather than
/// behind an actor.
public struct RunBatch: Hashable, Sendable {
    public var stitches: [PreviewStitch]

    /// The last pose in this batch, or the one carried in when the batch moved
    /// no needle — so a tick that only stitches still knows where the needle is.
    public var needle: PreviewNeedle?

    /// The design name a `writeEmbroideryToFile` brick asked for.
    ///
    /// This is the terminal marker, and it is the *only* one available here:
    /// none of US-306's completion reasons is an event. `programFinished` comes
    /// from `step()` returning `.finished`, `stoppedByUser` from task
    /// cancellation, `stitchLimitReached` from the frame budget. A pure fold
    /// over events cannot know any of them, and inventing a field for them
    /// would force the driver to synthesise values the events do not contain.
    public var requestedDesignName: String?

    public init(
        stitches: [PreviewStitch] = [],
        needle: PreviewNeedle? = nil,
        requestedDesignName: String? = nil
    ) {
        self.stitches = stitches
        self.needle = needle
        self.requestedDesignName = requestedDesignName
    }

    public static let empty = RunBatch()

    /// Folds one tick's events into a batch, carrying the previous needle pose
    /// so a tick that only stitches still knows where the needle is.
    ///
    /// The `switch` is exhaustive with no `default:` on purpose: a future
    /// `InterpreterEvent` case must force a decision here rather than being
    /// silently dropped into the preview's blind spot.
    public static func reducing(
        _ events: [InterpreterEvent],
        from carriedNeedle: PreviewNeedle? = nil
    ) -> RunBatch {
        var batch = RunBatch(needle: carriedNeedle)
        for event in events {
            switch event {
            case let .stitch(_, position, _, color):
                batch.stitches.append(PreviewStitch(position: position, color: color))
            case let .needleMoved(actor, update):
                batch.needle = PreviewNeedle(actor: actor, update: update)
            case let .finalizeRequested(name):
                batch.requestedDesignName = name
            case .colorArmed:
                // Deliberately ignored (ADR-021). It reports the brick's raw
                // *intent* — an unvalidated hex, emitted even when the manager
                // rejected it and even for the silent start — so consuming it
                // would mean re-deriving ADR-015 in the app. The resolved
                // colour already rides `.stitch`.
                continue
            case .waited:
                continue // no visible effect of its own
            }
        }
        return batch
    }

    /// Merges one tick's batch into this frame's batch.
    ///
    /// A frame may run more than one tick (`RunBudget.ticksPerFrame`), and the
    /// view model must still see **one** update — so the ticks are merged here
    /// rather than yielded separately. With the default `ticksPerFrame = 1` this
    /// runs once per frame and is the identity on an empty accumulator.
    ///
    /// This fold lived in the test target until US-306, as
    /// `PreviewFixtures.foldBatches`, whose own comment said it folded batches
    /// "the way US-306's driver will". It is hoisted rather than duplicated so the
    /// ADR-018 partition tests exercise the real fold instead of a parallel copy
    /// that could drift from it.
    ///
    /// The needle and the requested name are **carried forward** when the tick
    /// supplies neither: a tick that only stitches must not blank the pose, and a
    /// finalize request from an earlier tick of the same frame must survive a
    /// later one that makes none.
    public mutating func absorb(_ tick: RunBatch) {
        stitches += tick.stitches
        needle = tick.needle ?? needle
        requestedDesignName = tick.requestedDesignName ?? requestedDesignName
    }
}
