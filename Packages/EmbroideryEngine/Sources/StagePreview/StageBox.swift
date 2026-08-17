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
    ///
    /// **Precondition: both operands are well-ordered per axis** (`minX <= maxX`,
    /// `minY <= maxY`). Because the per-axis skip picks each edge independently from
    /// whichever operand is finite there, two boxes each poisoned on a *different* edge can
    /// otherwise produce an inverted result — `(minX: 300, maxX: .nan)` unioned with
    /// `(minX: .nan, maxX: 200)` gives `minX 300 > maxX 200`. Unreachable through
    /// `StageGeometry.fitTarget`, whose hoop operand is finite on every edge, and
    /// `StageTransform.fitting` stays total for an inverted box in any case — it falls back
    /// to scale 1 rather than trapping. Stated because this method is public
    /// (`swift-code-reviewer`, US-305).
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

    /// Assembles a box from two **independently accumulated** axes, or `nil` if either
    /// axis never saw a finite value.
    ///
    /// Per axis, because a box seeded per *point* is order-dependent (Codex round 1): an
    /// earlier fix required both coordinates to be finite before anything could seed the
    /// box, so a first stitch at `(.infinity, 1000)` contributed nothing and its perfectly
    /// good `y` was lost — while the *same pair in the opposite order* kept it. Splitting
    /// the axes makes the seed obey the same rule `expand(toInclude:)` already did.
    ///
    /// `nil` when an axis is empty is deliberate and not a half-measure: a `StageBox` has
    /// four edges, so a design with no finite `x` has no box to report, exactly as an empty
    /// list has none. `StageGeometry.fitTarget` already handles `nil` by falling back to
    /// the hoop; inventing an extent would be the actual error.
    init?(combining x: StageExtent?, _ y: StageExtent?) {
        guard let x, let y else { return nil }
        self.init(minX: x.min, minY: y.min, maxX: x.max, maxY: y.max)
    }

    /// Grows the box to include `point`, **skipping a non-finite coordinate per axis**.
    ///
    /// **This is a correctness fix, not hygiene** (`swift-code-reviewer`, US-305). ADR-021
    /// divergence #5 means a coordinate the stream *rejects* is still emitted and still
    /// drawn, and `changeXBy` accumulates without normalising — so two
    /// `greatestFiniteMagnitude` steps reach infinity from a perfectly legal program.
    /// Absorbing that infinity made `StitchDisplayList.bounds` infinite, which made
    /// `StageGeometry.fitTarget` collapse back to the hoop, which fitted a stitch 750 pt
    /// *outside* the hoop off-screen — the exact "silently cropped" outcome US-305's
    /// criterion forbids, and it silenced the hoop-overflow notice with it.
    ///
    /// Per axis rather than per point, so a stitch at `(.infinity, 400)` still
    /// contributes its perfectly good `y`.
    ///
    /// The invariant this establishes: **`bounds` covers exactly the finite positions.**
    /// `union`'s own non-finite skip is therefore the belt-and-braces its doc comment
    /// claims to be, rather than the only thing standing between a bad stitch and a
    /// cropped design.
    public mutating func expand(toInclude point: StagePoint) {
        if point.x.isFinite {
            minX = Swift.min(minX, point.x)
            maxX = Swift.max(maxX, point.x)
        }
        if point.y.isFinite {
            minY = Swift.min(minY, point.y)
            maxY = Swift.max(maxY, point.y)
        }
    }

    /// The from-scratch min/max over a sequence — the oracle `StitchDisplayList.bounds` is
    /// checked against, so that the incremental maintenance is proven rather than merely
    /// plausible. `nil` for an empty sequence: there is no such thing as the bounds of
    /// nothing.
    ///
    /// Skips non-finite coordinates on the same terms as `expand(toInclude:)`, including
    /// when looking for a seed — an oracle that disagreed with the thing it certifies
    /// would be worse than no oracle, since the differential test would fail for the wrong
    /// reason. `nil` therefore also means "nothing finite here".
    public static func containing(_ points: some Sequence<StagePoint>) -> StageBox? {
        var x: StageExtent?
        var y: StageExtent?
        for point in points {
            StageExtent.accumulate(&x, point.x)
            StageExtent.accumulate(&y, point.y)
        }
        return StageBox(combining: x, y)
    }
}

/// One axis of a `StageBox`, accumulated on its own.
///
/// Exists so that "skip a non-finite coordinate" is **one** rule covering both the first
/// value and every later one. When the seed and the expansion had separate rules they
/// disagreed, and bounds came out dependent on the order stitches arrived in (Codex
/// round 1).
struct StageExtent: Hashable, Sendable {
    var min: Double
    var max: Double

    /// `nil` for a non-finite value: an axis cannot start at infinity. ADR-021 divergence
    /// #5 makes that reachable from a legal program, since a coordinate the stream rejects
    /// is still emitted and still drawn.
    init?(_ value: Double) {
        guard value.isFinite else { return nil }
        min = value
        max = value
    }

    mutating func expand(to value: Double) {
        guard value.isFinite else { return }
        min = Swift.min(min, value)
        max = Swift.max(max, value)
    }

    /// Seeds or expands in one call — the shape both the incremental path
    /// (`StitchDisplayList.append`) and the oracle (`StageBox.containing`) need, so neither
    /// can drift from the other.
    static func accumulate(_ extent: inout StageExtent?, _ value: Double) {
        if extent == nil {
            extent = StageExtent(value)
        } else {
            extent?.expand(to: value)
        }
    }
}
