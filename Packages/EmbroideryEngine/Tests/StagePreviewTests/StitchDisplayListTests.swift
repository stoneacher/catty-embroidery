import EmbroideryEngine
import StagePreview
import Testing

@Suite("Stitch display list")
struct StitchDisplayListTests {
    @Test("an empty list has no bounds, no runs and nothing settled")
    func emptyList() {
        let list = StitchDisplayList()
        #expect(list.isEmpty)
        #expect(list.stitches.isEmpty)
        #expect(list.colorRuns.isEmpty)
        #expect(list.bounds == nil)
        #expect(list.settledCount == 0)
        #expect(list.liveTail.isEmpty)
    }

    @Test("appends preserve order")
    func appendsPreserveOrder() {
        let stitches = [previewStitch(0, 0), previewStitch(5, 1), previewStitch(-3, 9)]
        let list = displayList(stitches)
        #expect(list.stitches == stitches)
    }

    /// Gaplessness is the property US-305 relies on to draw one `Path` per run
    /// without scanning: every index belongs to exactly one run.
    @Test("color runs partition the indices with no gaps and no overlaps")
    func colorRunsPartitionTheIndices() {
        let list = displayList([
            previewStitch(0, 0, PreviewColor.red),
            previewStitch(1, 0, PreviewColor.red),
            previewStitch(2, 0, PreviewColor.green),
            previewStitch(3, 0, PreviewColor.red)
        ])

        #expect(list.colorRuns.map(\.color) == [PreviewColor.red, PreviewColor.green, PreviewColor.red])
        #expect(list.colorRuns.first?.range.lowerBound == 0)
        #expect(list.colorRuns.last?.range.upperBound == list.count)
        for (earlier, later) in zip(list.colorRuns, list.colorRuns.dropFirst()) {
            #expect(earlier.range.upperBound == later.range.lowerBound)
            #expect(earlier.color != later.color, "runs must be maximal, not merely contiguous")
        }
        #expect(list.colorRuns.allSatisfy { !$0.range.isEmpty })
        #expect(list.colorRuns.reduce(0) { $0 + $1.range.count } == list.count)
    }

    @Test("consecutive stitches of one color form a single run")
    func oneColorIsOneRun() {
        let list = displayList((0 ..< 500).map { previewStitch(Double($0), 0, PreviewColor.blue) })
        #expect(list.colorRuns.count == 1)
        #expect(list.colorRuns.first?.range == 0 ..< 500)
    }

    /// The counterpart extreme. Together with the test above these are the
    /// observable proxy for "append does not rescan": an implementation that
    /// rebuilt the runs per stitch gets both counts wrong, and one that merges
    /// too eagerly gets this one wrong.
    @Test("alternating colors form one run per stitch")
    func alternatingColorsFormOneRunEach() {
        let list = displayList((0 ..< 500).map {
            previewStitch(Double($0), 0, $0.isMultiple(of: 2) ? PreviewColor.red : PreviewColor.green)
        })
        #expect(list.colorRuns.count == 500)
    }

    @Test("bounds equal a from-scratch min and max")
    func boundsMatchTheFromScratchOracle() {
        let stitches = [
            previewStitch(0, 0), previewStitch(-12.5, 4), previewStitch(7, -3.25), previewStitch(2, 9)
        ]
        let list = displayList(stitches)
        #expect(list.bounds == StageBox.containing(stitches.map(\.position)))
        #expect(list.bounds == StageBox(minX: -12.5, minY: -3.25, maxX: 7, maxY: 9))
    }

    /// A design may legitimately leave ADR-007's stage, and the bounds must
    /// follow it there — `StageGeometry` describes the hoop, it does not bound
    /// anything.
    @Test("bounds follow a stitch outside the stage rather than clamping to it")
    func boundsFollowStitchesOutsideTheStage() throws {
        let list = displayList([previewStitch(0, 0), previewStitch(10000, 10000)])
        #expect(list.bounds?.maxX == 10000)
        #expect(list.bounds?.maxY == 10000)
        #expect(try #require(list.bounds?.maxX) > StageGeometry.box.maxX)
    }

    @Test("markSettled moves the live tail and nothing else")
    func markSettledMovesOnlyTheWatermark() {
        var list = displayList((0 ..< 10).map { previewStitch(Double($0), 0) })
        let before = list

        list.markSettled(upTo: 4)

        #expect(list.settledCount == 4)
        #expect(list.liveTail.count == 6)
        #expect(Array(list.liveTail) == Array(before.stitches[4...]))
        #expect(list.stitches == before.stitches)
        #expect(list.colorRuns == before.colorRuns)
        #expect(list.bounds == before.bounds)
    }

    /// Monotonic and clamped: going backwards would invalidate raster pixels
    /// the app still holds, and overshooting would put the watermark past the
    /// end of the array.
    @Test("markSettled is monotonic and clamped at both ends")
    func markSettledIsMonotonicAndClamped() {
        var list = displayList((0 ..< 10).map { previewStitch(Double($0), 0) })

        list.markSettled(upTo: 6)
        list.markSettled(upTo: 2)
        #expect(list.settledCount == 6, "must not go backwards")

        list.markSettled(upTo: .max)
        #expect(list.settledCount == 10, "must not run past the end")

        list.markSettled(upTo: -5)
        #expect(list.settledCount == 10)
    }

    @Test("appending after settling leaves the settled prefix untouched")
    func appendingKeepsTheSettledPrefixStable() {
        var list = displayList((0 ..< 10).map { previewStitch(Double($0), 0, PreviewColor.red) })
        list.markSettled(upTo: 10)
        let settledPrefix = Array(list.stitches)

        list.append(previewStitch(99, 99, PreviewColor.green))

        #expect(Array(list.stitches.prefix(10)) == settledPrefix)
        #expect(list.settledCount == 10)
        #expect(Array(list.liveTail) == [previewStitch(99, 99, PreviewColor.green)])
    }

    @Test("reset empties everything including the watermark")
    func resetEmptiesEverything() {
        var list = displayList((0 ..< 10).map { previewStitch(Double($0), 0, PreviewColor.red) })
        list.markSettled(upTo: 5)

        list.reset()

        #expect(list.isEmpty)
        #expect(list.colorRuns.isEmpty)
        #expect(list.bounds == nil)
        #expect(list.settledCount == 0)
        #expect(list.liveTail.isEmpty)
    }

    @Test("appending in batches gives the same list as appending one at a time")
    func batchedAndSingleAppendsAgree() {
        let stitches = (0 ..< 50).map {
            previewStitch(Double($0), Double($0 % 7), $0 % 3 == 0 ? PreviewColor.red : PreviewColor.green)
        }
        var oneAtATime = StitchDisplayList()
        for stitch in stitches {
            oneAtATime.append(stitch)
        }
        #expect(displayList(stitches) == oneAtATime)
    }
}

/// `resetCount`, added by US-305 for the stale-raster bug its declaration describes.
@Suite("Display list reset identity")
struct StitchDisplayListResetIdentityTests {
    @Test("a fresh list has never been reset")
    func aFreshListHasNeverBeenReset() {
        #expect(StitchDisplayList().resetCount == 0)
    }

    /// The property a cache key needs: two *different* runs that settle to the same count
    /// are distinguishable. Without this the key repeats and the previous design's raster
    /// is composited under the new design's live tail.
    @Test("two runs settled to the same count are still distinguishable")
    func twoRunsSettledToTheSameCountAreDistinguishable() {
        var list = displayList([previewStitch(0, 0), previewStitch(10, 0)])
        list.markSettled(upTo: 2)
        let firstKey = [list.settledCount, list.resetCount]

        list.reset()
        list.append(contentsOf: [previewStitch(50, 50), previewStitch(60, 50)])
        list.markSettled(upTo: 2)
        let secondKey = [list.settledCount, list.resetCount]

        #expect(list.settledCount == 2, "the counts deliberately do collide")
        #expect(firstKey != secondKey, "so something else has to break the tie")
    }

    @Test("the reset count is monotonic and survives appending")
    func theResetCountIsMonotonicAndSurvivesAppending() {
        var list = StitchDisplayList()
        list.reset()
        list.reset()
        list.append(previewStitch(0, 0))

        #expect(list.resetCount == 2)
    }
}
