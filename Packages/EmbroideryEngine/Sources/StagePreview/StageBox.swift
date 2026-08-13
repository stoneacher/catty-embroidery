import EmbroideryEngine

/// An axis-aligned rectangle in stage space (y-up, ADR-007).
///
/// Used for two different things that must not be confused: the extent of what
/// has actually been stitched (`StitchDisplayList.bounds`) and the hoop outline
/// (`StageGeometry.box`). Neither bounds the other — a design may legitimately
/// leave the stage.
public struct StageBox: Hashable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    /// The degenerate box at a single point — zero width and height. A
    /// one-stitch design has one of these, and `StageTransform.fitting` has to
    /// stay total for it.
    public init(containing point: StagePoint) {
        self.init(minX: point.x, minY: point.y, maxX: point.x, maxY: point.y)
    }

    public var width: Double {
        maxX - minX
    }

    public var height: Double {
        maxY - minY
    }

    /// Halved before summing, not after. `(minX + maxX) / 2` overflows to
    /// infinity for a box at extreme finite coordinates — a single stitch at
    /// `Double.greatestFiniteMagnitude` is enough — and the infinity then
    /// propagates into `StageTransform.fitting`'s translation, so a finite,
    /// valid design produces an unusable transform.
    ///
    /// Reachable in the preview specifically: ADR-021 makes the display list
    /// event-driven, and the event carries the stage point whether or not the
    /// *stream* later rejects it under ADR-020 — so export's conversion guard
    /// cannot protect this path. ADR-007 and `StageGeometry` deliberately bound
    /// nothing, which leaves this the only place to be careful.
    public var center: StagePoint {
        StagePoint(x: minX / 2 + maxX / 2, y: minY / 2 + maxY / 2)
    }

    /// The smallest box containing both — US-305's fit target is
    /// `union(hoop, contentBounds)`, so a design that leaves the hoop is *visible*
    /// rather than silently cropped.
    ///
    /// **Non-finite edges are skipped per axis, and that is the whole subtlety.**
    /// `Swift.min(a, .nan)` returns `a` while `Swift.min(.nan, a)` returns `.nan`,
    /// so the naive four-way min/max is order-dependent in the presence of NaN: it
    /// would either poison the result or silently discard a real extent, depending
    /// on which operand happened to be the receiver.
    ///
    /// This is reachable, not defensive: ADR-021 divergence #5 means a coordinate the
    /// stream *rejects* is still drawn, so `StitchDisplayList.bounds` can carry a
    /// non-finite edge — `center` above says the same thing about the same field.
    /// Skipping per axis means one bad stitch can neither delete the finite extent
    /// beside it nor shrink the union below the hoop.
    public func union(_ other: StageBox) -> StageBox {
        StageBox(
            minX: Self.lesser(minX, other.minX),
            minY: Self.lesser(minY, other.minY),
            maxX: Self.greater(maxX, other.maxX),
            maxY: Self.greater(maxY, other.maxY)
        )
    }

    /// `min`, treating a non-finite edge as absent. Returns the other operand
    /// unexamined when one is unusable — and `self` when both are, since there is no
    /// finite answer to give and the caller's box is the one with a claim to it.
    private static func lesser(_ first: Double, _ second: Double) -> Double {
        guard first.isFinite else { return second }
        guard second.isFinite else { return first }
        return Swift.min(first, second)
    }

    /// `max`, treating a non-finite edge as absent.
    private static func greater(_ first: Double, _ second: Double) -> Double {
        guard first.isFinite else { return second }
        guard second.isFinite else { return first }
        return Swift.max(first, second)
    }

    public mutating func expand(toInclude point: StagePoint) {
        minX = Swift.min(minX, point.x)
        minY = Swift.min(minY, point.y)
        maxX = Swift.max(maxX, point.x)
        maxY = Swift.max(maxY, point.y)
    }

    /// The from-scratch min/max over a sequence — the oracle
    /// `StitchDisplayList.bounds` is checked against, so that the incremental
    /// maintenance is proven rather than merely plausible. `nil` for an empty
    /// sequence: there is no such thing as the bounds of nothing.
    public static func containing(_ points: some Sequence<StagePoint>) -> StageBox? {
        var iterator = points.makeIterator()
        guard let first = iterator.next() else { return nil }
        var box = StageBox(containing: first)
        while let point = iterator.next() {
            box.expand(toInclude: point)
        }
        return box
    }
}
