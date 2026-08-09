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

    /// US-302 red phase: total but deliberately wrong; the green phase folds.
    public static func reducing(
        _ events: [InterpreterEvent],
        from carriedNeedle: PreviewNeedle? = nil
    ) -> RunBatch {
        _ = (events, carriedNeedle)
        return .empty
    }
}
