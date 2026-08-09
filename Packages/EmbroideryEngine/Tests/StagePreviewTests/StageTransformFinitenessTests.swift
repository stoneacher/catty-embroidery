import EmbroideryEngine
import StagePreview
import Testing

/// `StageTransform`'s numeric robustness, split from the geometry suite to stay
/// inside SwiftLint's file and type-body limits.
///
/// This suite exists because one floating-point product survived four rounds of
/// review, each fix closing the expression that had overflowed and leaving a
/// sibling: the midpoint, then the product, then the ceiling's rounding, then
/// `pinched`'s subtraction, then the viewport. The guarantee finally moved to
/// `StageTransform.init` — the one place a value of this type is made — and
/// these tests assert it from every direction rather than arguing for it.
@Suite("Stage transform finiteness")
struct StageTransformFinitenessTests {
    /// The Medium from Codex round 1. `StageBox.center` computed as
    /// `(minX + maxX) / 2` overflows to infinity at extreme finite
    /// coordinates, and the infinity propagates into the translation — so a
    /// finite, perfectly valid one-stitch design yields an unusable transform.
    ///
    /// Reachable through the preview because ADR-021 is event-driven: the event
    /// carries the stage point whether or not the *stream* later rejects it
    /// under ADR-020, and ADR-007 bounds nothing.
    @Test("an extreme but finite coordinate does not produce an infinite transform")
    func extremeFiniteCoordinateStaysFinite() throws {
        var list = StitchDisplayList()
        list.append(previewStitch(.greatestFiniteMagnitude, .greatestFiniteMagnitude))
        let bounds = try #require(list.bounds)
        expectUsableFit(bounds)
    }

    /// Every finite box must yield a finite, *usable* transform.
    ///
    /// The third case is the one round 1's fix missed (Codex round 2): the
    /// centre is finite there, but `centre.x × scale` still overflowed, because
    /// the *other* axis had an extent and pulled the scale above 1. Fixing the
    /// midpoint alone was not enough — the product needed bounding too.
    @Test(
        "every finite box yields a finite transform",
        arguments: [
            StageBox(
                minX: -.greatestFiniteMagnitude, minY: -.greatestFiniteMagnitude,
                maxX: .greatestFiniteMagnitude, maxY: .greatestFiniteMagnitude
            ),
            StageBox(
                minX: .greatestFiniteMagnitude, minY: 0,
                maxX: .greatestFiniteMagnitude, maxY: 1
            ),
            StageBox(
                minX: 0, minY: -.greatestFiniteMagnitude,
                maxX: 1, maxY: -.greatestFiniteMagnitude
            ),
            StageBox(containing: StagePoint(x: .leastNonzeroMagnitude, y: .leastNonzeroMagnitude)),
            // Codex round 3's brute-forced counterexample. The round-2 fix
            // bounded the scale by `greatestFiniteMagnitude / |centre|`, but
            // that division *rounds up*: here the ceiling comes back as
            // 1.2000448438435127 and `centre.x * scale` overflowed anyway.
            StageBox(
                minX: Double(bitPattern: 0x7FEA_AA69_5C4B_773D), minY: 0,
                maxX: Double(bitPattern: 0x7FEA_AA69_5C4B_773D), maxY: 1
            )
        ]
    )
    func everyFiniteBoxYieldsAFiniteTransform(_ bounds: StageBox) {
        expectUsableFit(bounds)
    }

    /// A search over the top binade, because the counterexample above was found
    /// by brute force rather than by reasoning — and reasoning about this
    /// product has now been wrong twice. A property this cheap to check should
    /// be checked rather than argued.
    @Test("no finite one-point box yields an infinite transform")
    func noFiniteBoxYieldsAnInfiniteTransform() {
        var bits: UInt64 = 0x7FE0_0000_0000_0000
        while bits < 0x7FF0_0000_0000_0000 {
            let value = Double(bitPattern: bits)
            let bounds = StageBox(minX: value, minY: 0, maxX: value, maxY: 1)
            let transform = StageTransform.fitting(bounds, in: ViewSize(width: 300, height: 300))
            #expect(transform.translation.x.isFinite, "overflowed at bit pattern \(bits)")
            #expect(transform.translation.y.isFinite, "overflowed at bit pattern \(bits)")
            bits &+= 0x0000_4000_0000_0000
        }
    }

    /// `pinched` multiplies a stage coordinate by the zoom exactly as `fitting`
    /// does, and the round-2 fix closed only `fitting` (Codex round 3). A zoom
    /// that cannot be represented is refused rather than returned as infinity.
    @Test("pinching a design at an extreme coordinate cannot produce an infinite transform")
    func pinchAtExtremeCoordinateStaysFinite() {
        let bounds = StageBox(containing: StagePoint(x: .greatestFiniteMagnitude, y: 0))
        let fitted = StageTransform.fitting(bounds, in: ViewSize(width: 300, height: 300))

        for factor in [0.5, 2.0, 1e6] {
            let pinched = fitted.pinched(by: factor, about: ViewPoint(x: 150, y: 150))
            #expect(pinched.scale.isFinite)
            #expect(pinched.translation.x.isFinite, "factor \(factor)")
            #expect(pinched.translation.y.isFinite, "factor \(factor)")
        }
    }

    /// The refusal must not leak into ordinary use: a normal design still zooms.
    @Test("an ordinary pinch is unaffected by the overflow guard")
    func ordinaryPinchStillZooms() {
        let transform = StageTransform(scale: 1, translation: ViewPoint(x: 10, y: 10))
        let pinched = transform.pinched(by: 2, about: ViewPoint(x: 100, y: 100))
        #expect(pinched.scale == 2)
        #expect(pinched != transform)
    }

    // MARK: - The chokepoint

    /// The invariant, asserted directly: **no `StageTransform` can hold a
    /// non-finite field**, whatever it was constructed from. Four review rounds
    /// each patched the expression that had overflowed and left a sibling, so
    /// the guarantee moved to the one place a value of this type is made.
    @Test(
        "no construction can produce a non-finite transform",
        arguments: [Double.infinity, -.infinity, .nan, .greatestFiniteMagnitude]
    )
    func constructionAlwaysYieldsFiniteFields(_ hostile: Double) {
        let transform = StageTransform(
            scale: hostile, translation: ViewPoint(x: hostile, y: hostile)
        )
        #expect(transform.scale.isFinite)
        #expect(transform.translation.x.isFinite)
        #expect(transform.translation.y.isFinite)
        #expect(transform.scale >= StageTransform.minimumScale)
    }

    /// Codex round 4's `fitting` counterexample. The round-3 fix bounded
    /// `content × scale` but not `viewportCentre − content × scale`, and the
    /// test helper's fixed 300×300 viewport is exactly what hid it — the
    /// viewport has to be hostile too.
    @Test("a vast viewport cannot produce an infinite transform")
    func vastViewportStaysFinite() {
        let magnitude = Double.greatestFiniteMagnitude
        let bounds = StageBox(minX: -magnitude / 50, minY: 0, maxX: -magnitude / 100, maxY: 1)
        let transform = StageTransform.fitting(
            bounds, in: ViewSize(width: magnitude, height: magnitude)
        )
        #expect(transform.translation.x.isFinite)
        #expect(transform.translation.y.isFinite)
    }

    /// Codex round 4's `pinched` counterexample: the product is finite and the
    /// *subtraction* is not.
    ///
    /// Asserts **identity**, not finiteness (Codex round 5). "Refused" means
    /// the transform is unchanged; a version that silently reset or repositioned
    /// it would also be finite, and the earlier assertion could not tell the
    /// two apart — the same mis-targeting this branch has now hit five times.
    @Test("a pinch whose translation overflows is refused rather than returned")
    func pinchWithOverflowingSubtractionIsRefused() {
        let magnitude = Double.greatestFiniteMagnitude
        let transform = StageTransform(
            scale: 0.05, translation: ViewPoint(x: 0.81 * magnitude, y: 0)
        )
        let result = transform.pinched(by: 50, about: ViewPoint(x: 0.8 * magnitude, y: 0))
        #expect(result == transform, "an unrepresentable pinch leaves the transform alone")
    }

    @Test("a drag that would overflow is refused, including by accumulation")
    func draggingCannotOverflow() {
        let magnitude = Double.greatestFiniteMagnitude
        var transform = StageTransform(scale: 1, translation: ViewPoint(x: 0.9 * magnitude, y: 0))
        for _ in 0 ..< 5 {
            transform = transform.dragged(by: ViewPoint(x: 0.5 * magnitude, y: 0))
            #expect(transform.translation.x.isFinite)
        }
        let refused = transform.dragged(by: ViewPoint(x: .infinity, y: 0))
        #expect(refused == transform, "an unrepresentable drag leaves the transform alone")
    }

    /// A huge zoom-in must not become the maximum zoom-*out* (Codex round 5).
    /// `scale × factor` overflows to `+∞`, and the original `clampedScale`
    /// mapped every non-finite value to `minimumScale` — so pinching in by an
    /// enormous factor threw the design away. Wrong-but-finite, and visible.
    @Test("an overflowing zoom-in clamps to maximum zoom, not minimum")
    func overflowingZoomInClampsToMaximum() {
        let transform = StageTransform(scale: 2)
        let zoomedIn = transform.pinched(by: .greatestFiniteMagnitude, about: .zero)
        #expect(zoomedIn.scale == StageTransform.maximumScale)

        let zoomedOut = transform.pinched(by: -.infinity, about: .zero)
        #expect(zoomedOut.scale == StageTransform.minimumScale)
    }

    @Test("clampedScale preserves direction at the infinities")
    func clampedScalePreservesDirection() {
        #expect(StageTransform.clampedScale(.infinity) == StageTransform.maximumScale)
        #expect(StageTransform.clampedScale(-.infinity) == StageTransform.minimumScale)
        #expect(StageTransform.clampedScale(.nan) == StageTransform.minimumScale)
    }

    /// The sweep the fixed-viewport helper could not do: hostile content
    /// against hostile viewports, asserting the type invariant holds
    /// throughout. Cheap, and the reasoning it replaces was wrong four times.
    @Test("fitting is total across hostile content and hostile viewports")
    func fittingIsTotalAcrossHostileInputs() {
        let magnitude = Double.greatestFiniteMagnitude
        let extremes = [
            -magnitude, -magnitude / 2, -magnitude / 100, -1e300, 0, 1e300,
            magnitude / 100, magnitude / 2, magnitude
        ]
        let viewports = [
            ViewSize(width: 0, height: 0),
            ViewSize(width: 300, height: 300),
            ViewSize(width: magnitude, height: magnitude),
            ViewSize(width: magnitude, height: 1)
        ]
        for minX in extremes {
            for maxX in extremes where maxX >= minX {
                for viewport in viewports {
                    let bounds = StageBox(minX: minX, minY: 0, maxX: maxX, maxY: 1)
                    let transform = StageTransform.fitting(bounds, in: viewport)
                    #expect(
                        transform.translation.x.isFinite && transform.translation.y.isFinite,
                        "box \(minX)…\(maxX) in \(viewport.width)×\(viewport.height)"
                    )
                    #expect(transform.scale.isFinite)
                }
            }
        }
    }

    /// Finiteness of the *fields* is not usability — round 1's version stopped
    /// there and would have passed while the transform mapped every point to
    /// something unusable. The mapping itself has to stay finite.
    private func expectUsableFit(
        _ bounds: StageBox,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(bounds.center.x.isFinite, sourceLocation: sourceLocation)
        #expect(bounds.center.y.isFinite, sourceLocation: sourceLocation)

        let transform = StageTransform.fitting(bounds, in: ViewSize(width: 300, height: 300))
        #expect(transform.scale.isFinite, sourceLocation: sourceLocation)
        #expect(transform.scale > 0, sourceLocation: sourceLocation)
        #expect(transform.translation.x.isFinite, sourceLocation: sourceLocation)
        #expect(transform.translation.y.isFinite, sourceLocation: sourceLocation)

        // Every corner maps finitely — the contract `fitting` restored in round
        // 6 after round 5 wrongly concluded it was unachievable and weakened it.
        let corners = [
            bounds.center,
            StagePoint(x: bounds.minX, y: bounds.minY),
            StagePoint(x: bounds.maxX, y: bounds.minY),
            StagePoint(x: bounds.minX, y: bounds.maxY),
            StagePoint(x: bounds.maxX, y: bounds.maxY)
        ]
        for corner in corners {
            let mapped = transform.viewPoint(of: corner)
            #expect(mapped.x.isFinite, "corner \(corner)", sourceLocation: sourceLocation)
            #expect(mapped.y.isFinite, "corner \(corner)", sourceLocation: sourceLocation)
        }
    }

    /// Codex round 5's counterexample — and the correction of round 5's own
    /// conclusion about it (Codex round 6).
    ///
    /// I originally shipped this as a *characterisation* test asserting the far
    /// corner maps to infinity, on the reasoning that no implementation could
    /// do better. That was false: at scale 0.5 both corners map finitely, and
    /// the fit had merely fallen back to scale 1 because an overflowed content
    /// width and a zero-height viewport made the computed fit zero. Writing the
    /// defect into a test is a worse outcome than leaving it unfixed, because
    /// it converts a bug into a specification. The test now demands what a
    /// caller actually needs.
    @Test("range-spanning content still maps every corner finitely")
    func rangeSpanningContentMapsFinitely() {
        let magnitude = Double.greatestFiniteMagnitude
        let bounds = StageBox(minX: -magnitude, minY: 0, maxX: 1e300, maxY: 1)
        let transform = StageTransform.fitting(bounds, in: ViewSize(width: magnitude, height: 1))

        #expect(transform.scale.isFinite)
        #expect(transform.translation.x.isFinite)
        #expect(transform.translation.y.isFinite)

        for x in [bounds.minX, bounds.maxX] {
            for y in [bounds.minY, bounds.maxY] {
                let mapped = transform.viewPoint(of: StagePoint(x: x, y: y))
                #expect(mapped.x.isFinite, "corner (\(x), \(y))")
                #expect(mapped.y.isFinite, "corner (\(x), \(y))")
            }
        }
    }

    /// The sweep, strengthened to the restored contract: across hostile content
    /// and hostile viewports, **every one of the four corners** maps finitely —
    /// not merely the transform's own fields, which is what round 5's weakened
    /// contract had given up on.
    ///
    /// **Both axes vary independently, and the viewport dimensions are a cross
    /// product** (Codex round 7). The earlier version varied only x, pinned
    /// `minY = 0` / `maxY = 1`, and mapped only `y: 0` — so a y-flip, a
    /// height-fit or a y-translation overflow could regress while it stayed
    /// green. That is the **third** time on this branch a test meant to be
    /// exhaustive held an input constant, which is why the shape is spelled out
    /// here rather than left to the next reader to notice.
    @Test("fitting maps all four corners finitely across hostile content and viewports")
    func fittingMapsCornersAcrossHostileInputs() {
        let magnitude = Double.greatestFiniteMagnitude
        let extremes = [-magnitude, -magnitude / 100, -1e300, 0, 1e300, magnitude / 100, magnitude]
        let dimensions = [0.0, 1, 300, magnitude]

        for minX in extremes {
            for maxX in extremes where maxX >= minX {
                for minY in extremes {
                    for maxY in extremes where maxY >= minY {
                        let bounds = StageBox(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
                        for width in dimensions {
                            for height in dimensions {
                                expectAllCornersMapFinitely(
                                    bounds, in: ViewSize(width: width, height: height)
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func expectAllCornersMapFinitely(
        _ bounds: StageBox,
        in viewport: ViewSize,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let transform = StageTransform.fitting(bounds, in: viewport)
        for x in [bounds.minX, bounds.maxX] {
            for y in [bounds.minY, bounds.maxY] {
                let mapped = transform.viewPoint(of: StagePoint(x: x, y: y))
                #expect(
                    mapped.x.isFinite && mapped.y.isFinite,
                    """
                    corner (\(x), \(y)) of \(bounds.minX)…\(bounds.maxX) × \
                    \(bounds.minY)…\(bounds.maxY) in \(viewport.width)×\(viewport.height)
                    """,
                    sourceLocation: sourceLocation
                )
            }
        }
    }
}
