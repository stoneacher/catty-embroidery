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

/// The ADR-012 rounding rule: Java `Math.round` = `floor(x + 0.5)`, which
/// differs from Swift `.rounded()` on negative halves (−6.5 → −6, not −7).
/// Every stage-space rounding in the engine goes through this.
func javaRound(_ value: Double) -> Double {
    (value + 0.5).rounded(.down)
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
    /// `javaRound` per axis. No y-flip: stage y-up maps straight to DST +Y
    /// (ADR-007/ADR-012).
    public init(converting stagePoint: StagePoint) {
        self.init(
            x: Self.embroideryUnits(fromStageValue: stagePoint.x),
            y: Self.embroideryUnits(fromStageValue: stagePoint.y)
        )
    }

    /// Stage points → embroidery units factor (Catroid `STITCH_POINT_UNIT_FACTOR`).
    public static let stitchPointUnitFactor = 2.0

    /// Internal so the interpolation split decision can convert a stage
    /// *difference* (Catroid `toEmbroideryUnit` in `getMaxDistanceBetweenPoints`)
    /// — the one place ADR-012 allows converting a difference, decision only.
    static func embroideryUnits(fromStageValue value: Double) -> Int {
        Int(javaRound(value * stitchPointUnitFactor))
    }
}
