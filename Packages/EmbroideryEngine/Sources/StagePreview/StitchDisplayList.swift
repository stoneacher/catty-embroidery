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
/// `Equatable` but deliberately **not** `Hashable`: nothing needs a hash, and
/// `hash(into:)` over 50 000 stitches would be unconditionally O(n) with no
/// copy-on-write fast path — a trap for anyone who put the list in a `Set` or
/// used it as a dictionary key. `Array.==` at least short-circuits on shared
/// storage (`swift-code-reviewer`, US-302).
public struct StitchDisplayList: Equatable, Sendable {
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

    /// How many times this list has been `reset()`.
    ///
    /// **What it exists for: telling two designs apart that settled to the same count.**
    /// A renderer caching the settled prefix keys its raster on `settledCount` — sound
    /// under append-only, because a prefix can never change. `reset()` breaks exactly that
    /// premise: afterwards, the same count describes different pixels. So a US-306 driver
    /// that runs design A to a watermark of *k*, then switches to design B and re-settles
    /// to the same *k* in the same viewport, would find a matching cache key and composite
    /// **A's raster under B's live tail** — and the fitted transform cannot break the tie,
    /// because ADR-024 records as a *benefit* that it is identical for every in-hoop
    /// design.
    ///
    /// Latent rather than live: nothing in US-305 advances the watermark, so the bake path
    /// is unreachable today and no test could have caught this at runtime
    /// (`swift-code-reviewer`, US-305). Added now because the fix is one integer and the
    /// bug would first appear as a wrong image in a story that did not cause it.
    public private(set) var resetCount = 0

    public init() {}

    public var count: Int {
        stitches.count
    }

    public var isEmpty: Bool {
        stitches.isEmpty
    }

    /// The stitches after the rasterisation watermark — the only ones a frame
    /// has to redraw.
    ///
    /// **Do not store the returned slice.** An `ArraySlice` retains the whole
    /// backing buffer, so a slice held across the next `append` makes the
    /// storage non-uniquely referenced and turns that append into a full copy
    /// of every stitch — which silently converts `append`'s O(N) into O(M + N)
    /// exactly where it matters, in the per-frame path. Measured at 50 000
    /// stitches: one reallocation *per frame* and ~1.2 MB copied, versus zero
    /// when nothing is retained (`swift-code-reviewer`, US-302).
    ///
    /// Use `withLiveTail(_:)` for a scoped read, which cannot outlive the call.
    /// If a renderer genuinely needs to keep the tail beyond the frame,
    /// `Array(list.liveTail)` is the **cheaper** option, not the more expensive
    /// one: it copies only the tail and leaves the list's buffer unique.
    public var liveTail: ArraySlice<PreviewStitch> {
        stitches[settledCount...]
    }

    /// Reads the live tail within `body`, without giving the caller a slice it
    /// could accidentally retain past the next append. Preferred over
    /// `liveTail` for per-frame rendering.
    public func withLiveTail<Result>(
        _ body: (ArraySlice<PreviewStitch>) throws -> Result
    ) rethrows -> Result {
        try body(stitches[settledCount...])
    }

    /// Appends one stitch, extending the derived state in place.
    ///
    /// O(1), and that is a requirement rather than an observation: nothing here
    /// may scan `stitches` or `colorRuns`, so appending N stitches to a list
    /// already holding M costs O(N) whatever M is. At the 50 000-stitch exit
    /// criterion a per-append rescan would be quadratic.
    ///
    /// That amortised O(N) additionally assumes the buffer is **uniquely
    /// referenced** — see `liveTail`, which is the one easy way for a caller to
    /// break it.
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

        // `finitelyContaining`, so a rejected coordinate cannot *seed* the box. Together
        // with `expand`'s per-axis skip this makes `bounds` cover exactly the finite
        // positions — without the seed guard, a design whose **first** stitch is
        // unconvertible had infinite bounds forever after, and US-305's fit target then
        // cropped the genuinely out-of-hoop stitches it exists to keep on screen
        // (`swift-code-reviewer`, US-305).
        if bounds == nil {
            bounds = StageBox(finitelyContaining: stitch.position)
        } else {
            bounds?.expand(toInclude: stitch.position)
        }
    }

    /// Appends a batch — one `RunBatch` per tick, in the US-306 path.
    ///
    /// **No `reserveCapacity` here, deliberately.** An earlier version reserved
    /// `count + underestimatedCount` on every call, intending an optimisation
    /// and getting the opposite twice over (`swift-code-reviewer`, US-302):
    ///
    /// - `Array.reserveCapacity` requests an *exact* capacity, which defeats
    ///   the geometric growth `append` would otherwise use. Building 50 000
    ///   stitches in batches of 10 measured **96 reallocations / 0.69 ms with
    ///   the reserve against 13 / 0.07 ms without** it.
    /// - Worse per-frame: `reserveCapacity` copies whenever the buffer is not
    ///   uniquely referenced, *regardless of capacity*. With a renderer holding
    ///   a copy, a tick producing **no stitches at all** — routine, since a
    ///   `wait` or a non-stitch brick yields an empty batch — still paid a full
    ///   1.2 MB copy. A plain append loop over zero elements costs nothing.
    public mutating func append(contentsOf newStitches: some Sequence<PreviewStitch>) {
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
        // Monotonic, and deliberately **not** reset by anything: it is an identity for the
        // run, not a count of live state. See its declaration for the stale-raster bug it
        // exists to prevent.
        resetCount += 1
    }
}
