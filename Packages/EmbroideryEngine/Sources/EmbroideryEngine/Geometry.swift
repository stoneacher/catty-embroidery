/// A point in stage space (ADR-007): center origin, y-up, 500×500 pt virtual
/// stage where 1 pt = 2 embroidery units = 0.2 mm.
public struct StagePoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A point in embroidery units (0.1 mm, the DST coordinate grid).
public struct EmbroideryPoint: Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    /// Converts a stage point to embroidery units: factor 2.0, then
    /// `floor(v + 0.5)` per axis — Java `Math.round` semantics, which differ
    /// from Swift `.rounded()` on negative halves (−6.5 → −6, not −7).
    /// No y-flip: stage y-up maps straight to DST +Y (ADR-007/ADR-012).
    public init(converting stagePoint: StagePoint) {
        self.init(
            x: Self.embroideryUnits(fromStageValue: stagePoint.x),
            y: Self.embroideryUnits(fromStageValue: stagePoint.y)
        )
    }

    /// Stage points → embroidery units factor (Catroid `STITCH_POINT_UNIT_FACTOR`).
    public static let stitchPointUnitFactor = 2.0

    private static func embroideryUnits(fromStageValue value: Double) -> Int {
        Int((value * stitchPointUnitFactor + 0.5).rounded(.down))
    }
}
