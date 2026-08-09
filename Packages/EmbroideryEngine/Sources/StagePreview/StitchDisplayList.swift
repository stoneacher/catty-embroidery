import EmbroideryEngine

/// The preview's model of what has been stitched: append-only, never reordered
/// (ADR-021).
///
/// Append-only is the load-bearing property, not an implementation detail. It
/// is what makes ADR-009's "rasterise the settled prefix, redraw only the live
/// tail" sound: a prefix that can never change is a prefix whose pixels stay
/// valid. `assembled()` cannot offer that — it replays `layerOps.keys.sorted()`
/// and a new stitch on a lower layer inserts into the middle of the result.
///
/// A value type, deliberately. The package is `Sendable` value types
/// throughout, and US-306's `@Observable` view model holds one of these as a
/// property so that appending a batch is literally one observable mutation. A
/// reference type would leave the property unchanged and the observation would
/// not fire.
public struct StitchDisplayList: Hashable, Sendable {
    /// A maximal run of consecutive stitches sharing a thread colour. The runs
    /// form a **gapless partition** of `stitches.indices`, which is what lets
    /// US-305 draw one `Path` per colour without scanning.
    public struct ColorRun: Hashable, Sendable {
        public let color: ThreadColor
        public fileprivate(set) var range: Range<Int>
    }

    public private(set) var stitches: [PreviewStitch] = []
    public private(set) var colorRuns: [ColorRun] = []
    public private(set) var bounds: StageBox?

    /// How many leading stitches the renderer has committed to its cached
    /// raster. Monotonic: only `reset()` may take it back, because moving it
    /// backwards would silently invalidate pixels the app still holds.
    public private(set) var settledCount = 0

    public init() {}

    public var count: Int {
        stitches.count
    }

    public var isEmpty: Bool {
        stitches.isEmpty
    }

    /// The stitches after the rasterisation watermark — the only ones a frame
    /// has to redraw. A slice, not a copy.
    public var liveTail: ArraySlice<PreviewStitch> {
        stitches[settledCount...]
    }

    /// Appends one stitch, extending the derived state in place.
    ///
    /// O(1), and that is a requirement rather than an observation: nothing here
    /// may scan `stitches` or `colorRuns`, so appending N stitches to a list
    /// already holding M costs O(N) whatever M is. At the 50 000-stitch exit
    /// criterion a per-append rescan would be quadratic.
    ///
    /// The runs stay a gapless partition by construction — a new run always
    /// starts exactly where the previous one ended — rather than by a repair
    /// pass that could be got wrong.
    public mutating func append(_ stitch: PreviewStitch) {
        let index = stitches.count
        stitches.append(stitch)

        if colorRuns.isEmpty || colorRuns[colorRuns.count - 1].color != stitch.color {
            colorRuns.append(ColorRun(color: stitch.color, range: index ..< index + 1))
        } else {
            colorRuns[colorRuns.count - 1].range = colorRuns[colorRuns.count - 1].range
                .lowerBound ..< index + 1
        }

        if bounds == nil {
            bounds = StageBox(containing: stitch.position)
        } else {
            bounds?.expand(toInclude: stitch.position)
        }
    }

    public mutating func append(contentsOf newStitches: some Sequence<PreviewStitch>) {
        stitches.reserveCapacity(stitches.count + newStitches.underestimatedCount)
        for stitch in newStitches {
            append(stitch)
        }
    }

    /// Advances the rasterisation watermark. Monotonic and clamped: moving it
    /// backwards would silently invalidate pixels the renderer still holds, and
    /// only `reset()` legitimately takes it back.
    public mutating func markSettled(upTo count: Int) {
        settledCount = Swift.max(settledCount, Swift.min(count, stitches.count))
    }

    /// Empties the list for a fresh run — the one operation allowed to move the
    /// watermark backwards, because there are no settled pixels left to protect.
    public mutating func reset() {
        stitches.removeAll(keepingCapacity: true)
        colorRuns.removeAll(keepingCapacity: true)
        bounds = nil
        settledCount = 0
    }
}
