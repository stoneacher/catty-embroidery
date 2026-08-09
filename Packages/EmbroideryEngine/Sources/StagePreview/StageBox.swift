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

    public var center: StagePoint {
        StagePoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
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
