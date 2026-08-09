import EmbroideryEngine

/// One stitch as the preview draws it: where the needle went, and in which
/// thread.
///
/// The colour arrives already resolved on `InterpreterEvent.stitch` (ADR-021),
/// so nothing here re-derives ADR-015. `.black` is a perfectly ordinary value —
/// it is `ColorState`'s default, so an object that never set a colour stitches
/// black — and is *not* a marker for the export model's clause-B records.
///
/// Deliberately carries neither `layer` nor `actor`. No M3 consumer needs
/// them: US-305 draws per colour run, US-306 needs the needle pose (which
/// `RunBatch` carries separately), US-307 needs the bounds and the runs. More
/// than that, a stored layer would invite a layer-ordered redraw — which is
/// precisely the mid-array insertion ADR-021 rejects `assembled()` for. This
/// list's whole value is that it is emission-ordered and append-only. Both
/// fields stay purely additive if a later milestone earns them.
public struct PreviewStitch: Hashable, Sendable {
    public var position: StagePoint
    public var color: ThreadColor

    public init(position: StagePoint, color: ThreadColor) {
        self.position = position
        self.color = color
    }
}
