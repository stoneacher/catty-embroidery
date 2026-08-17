import EmbroideryEngine

/// The three windows a frame needs, and the single planner behind them.
///
/// One planner parameterised by two windows, rather than three implementations:
/// settled and live pixels must be produced by the same rules or the seam at the
/// watermark will differ visibly in cap shape, width or alpha, and no unit test would
/// notice.
public extension StitchDrawPlan {
    /// Everything in the list — the no-raster path, and what a frame draws while the
    /// design is still small enough that baking costs more than it saves.
    static func entire(of list: StitchDisplayList) -> StitchDrawPlan {
        planning(
            list,
            dotting: 0 ..< list.count,
            segmentsFrom: 0,
            upTo: lastSegment(before: list.count)
        )
    }

    /// What the cached raster bakes: strictly *inside* the watermark.
    static func settled(of list: StitchDisplayList) -> StitchDrawPlan {
        planning(
            list,
            dotting: 0 ..< list.settledCount,
            segmentsFrom: 0,
            upTo: lastSegment(before: list.settledCount)
        )
    }

    /// What each frame redraws over the raster.
    ///
    /// **It starts one segment earlier than the dots do, and that is the point.** The
    /// watermark splits *stitches*, but a segment joins two of them, so segment
    /// `(k−1, k)` straddles it and belongs to neither window under the obvious
    /// reading — leaving a permanent one-segment gap in the thread at every watermark
    /// advance. (US-305's own test plan asked for exactly that obvious reading; the
    /// story records the correction.)
    ///
    /// Sound because the display list is append-only **per element**, not merely per
    /// prefix: stitch `k − 1` can never change once appended, so redrawing its
    /// outgoing segment every frame is free of risk, and when the watermark passes it
    /// the raster picks the segment up. The two windows stay disjoint, so a
    /// traversal's alpha is never composited twice.
    ///
    /// Note this needs stitch `k − 1`, which is *outside* `liveTail`. Indexing
    /// `stitches` is correct here; reaching for the slice and keeping it is what
    /// ADR-021 forbids.
    static func live(of list: StitchDisplayList) -> StitchDrawPlan {
        planning(
            list,
            dotting: list.settledCount ..< list.count,
            segmentsFrom: lastSegment(before: list.settledCount),
            upTo: lastSegment(before: list.count)
        )
    }

    /// The number of segments wholly below `count` stitches: `count − 1`, floored at
    /// zero so an empty or one-stitch list stays total. Both windows are expressed in
    /// terms of this, so the off-by-one lives in one place.
    private static func lastSegment(before count: Int) -> Int {
        Swift.max(0, count - 1)
    }

    /// Groups one window into strokes and dot runs.
    ///
    /// Walks `colorRuns` rather than the stitches: the runs are a gapless partition of
    /// the indices (`StitchDisplayList` guarantees it), so every drawn segment lies
    /// wholly inside exactly one run and nothing needs a scan to find out which.
    ///
    /// A segment that *crosses* runs is never emitted, because a run contributes only
    /// the segments whose both endpoints it holds — so the suppression rule is
    /// enforced by the iteration, and the classifier's `.suppressed` result is a
    /// second, independent check rather than the only one.
    private static func planning(
        _ list: StitchDisplayList,
        dotting dotted: Range<Int>,
        segmentsFrom firstSegment: Int,
        upTo lastSegment: Int
    ) -> StitchDrawPlan {
        var plan = StitchDrawPlan()
        let segments = firstSegment ..< lastSegment

        for run in list.colorRuns {
            plan.strokes += strokes(for: run, of: list, within: segments)
        }
        for run in list.colorRuns {
            if let indices = run.range.clamped(within: dotted) {
                plan.dots.append(DotRun(color: run.color, indices: indices))
            }
        }
        return plan
    }

    /// The at-most-two strokes one colour run contributes: traversal first, so travel
    /// hints sit *under* the thread rather than over it.
    private static func strokes(
        for run: StitchDisplayList.ColorRun,
        of list: StitchDisplayList,
        within window: Range<Int>
    ) -> [Stroke] {
        // Segment `i` belongs to this run only if it holds both `i` and `i + 1`.
        let owned = run.range.lowerBound ..< Swift.max(run.range.lowerBound, run.range.upperBound - 1)
        guard let candidates = owned.clamped(within: window) else { return [] }

        var threaded: [Int] = []
        var traversed: [Int] = []
        for start in candidates {
            switch StitchSegmentStyle.classifying(
                from: list.stitches[start], to: list.stitches[start + 1]
            ) {
            case .thread: threaded.append(start)
            case .traversal: traversed.append(start)
            case .suppressed: continue // cannot arise inside a run; see `planning`
            }
        }

        var strokes: [Stroke] = []
        if !traversed.isEmpty {
            strokes.append(Stroke(style: .traversal, color: run.color, segmentStarts: traversed))
        }
        if !threaded.isEmpty {
            strokes.append(Stroke(style: .thread, color: run.color, segmentStarts: threaded))
        }
        return strokes
    }
}

private extension Range<Int> {
    /// The overlap with `other`, or `nil` when they do not meet.
    ///
    /// Not `Range.clamped(to:)`, which returns an *empty* range rather than `nil` for
    /// disjoint inputs — and an empty range is exactly what the plan's "no stroke is
    /// ever empty" invariant needs to distinguish from a real one.
    func clamped(within other: Range<Int>) -> Range<Int>? {
        let lower = Swift.max(lowerBound, other.lowerBound)
        let upper = Swift.min(upperBound, other.upperBound)
        return lower < upper ? lower ..< upper : nil
    }
}
