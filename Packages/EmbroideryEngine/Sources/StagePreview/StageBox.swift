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
