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
    ///
    /// Fails instead of trapping for a coordinate the grid cannot hold — NaN,
    /// ±∞, or a finite value whose ×2 conversion leaves `Int` range (ADR-020).
    /// Failable rather than paired with a predicate so the trap is
    /// unrepresentable at the type level: `EmbroideryStream.append` is the one
    /// production caller, and it drops the stitch, ADR-014 style.
    public init?(converting stagePoint: StagePoint) {
        guard let x = Self.embroideryUnits(fromStageValue: stagePoint.x),
              let y = Self.embroideryUnits(fromStageValue: stagePoint.y)
        else { return nil }
        self.init(x: x, y: y)
    }

    /// Stage points → embroidery units factor (Catroid `STITCH_POINT_UNIT_FACTOR`).
    public static let stitchPointUnitFactor = 2.0

    /// Internal so the interpolation split decision can convert a stage
    /// *difference* (Catroid `toEmbroideryUnit` in `getMaxDistanceBetweenPoints`)
    /// — the one place ADR-012 allows converting a difference, decision only.
    /// `Int(exactly:)` carries the whole ADR-020 guard: it rejects non-finite
    /// and out-of-range values in one expression, with no bound to keep in
    /// sync by hand. `javaRound` always yields an integral `Double`, so the
    /// initializer's third rejection reason never fires.
    static func embroideryUnits(fromStageValue value: Double) -> Int? {
        Int(exactly: javaRound(value * stitchPointUnitFactor))
    }

    /// Catroid `DSTFileConstants.getMaxDistanceBetweenPoints`: Chebyshev
    /// distance with each stage-space axis difference converted to embroidery
    /// units first. Takes the differences already computed, because the two
    /// callers subtract in *opposite* orders and must keep doing so — the
    /// stream rounds `target − previous` (`DSTStream`) and the pattern
    /// manager's clauses round `previous − target`, and `javaRound`'s
    /// asymmetry at negative halves makes that difference load-bearing
    /// (ADR-015).
    ///
    /// An unrepresentable difference saturates to `Int.max` rather than
    /// trapping (ADR-020): the result is only ever compared against a
    /// threshold, so "cannot be converted" and "farther than any threshold"
    /// are the same answer.
    static func distanceInUnits(dx: Double, dy: Double) -> Int {
        max(axisDistance(dx), axisDistance(dy))
    }

    private static func axisDistance(_ difference: Double) -> Int {
        // Via `magnitude`, not `abs`: `Int(exactly:)` can return `Int.min`,
        // whose negation is not an `Int`.
        guard let units = embroideryUnits(fromStageValue: difference),
              let distance = Int(exactly: units.magnitude)
        else { return .max }
        return distance
    }
}
