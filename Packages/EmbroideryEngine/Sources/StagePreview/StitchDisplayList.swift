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

    /// US-302 red phase: stores the stitch but maintains none of the derived
    /// state, so the suite fails on what it is testing instead of trapping on
    /// an empty array — a crash takes its whole parallel suite with it.
    public mutating func append(_ stitch: PreviewStitch) {
        stitches.append(stitch)
    }

    /// US-302 red phase: total but deliberately wrong; the green phase appends.
    public mutating func append(contentsOf newStitches: some Sequence<PreviewStitch>) {
        for stitch in newStitches {
            append(stitch)
        }
    }

    /// US-302 red phase: total but deliberately wrong; the green phase advances.
    public mutating func markSettled(upTo count: Int) {
        _ = count
    }

    /// US-302 red phase: total but deliberately wrong; the green phase empties.
    public mutating func reset() {}
}
