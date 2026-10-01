@testable import catrobat_embroidery_ios
import StagePreview
import SwiftUI
import Testing

/// What the hoop field is drawn as, now that it is drawn by the renderer's own `Canvas`.
///
/// **US-315 moved the field into the stitch `Canvas`**, because two sibling `Canvas` views were
/// presented under different geometry while the stage's frame animated: the hoop and the design
/// came apart for a few frames whenever the keyboard moved. No unit test can see that — it lives
/// in how SwiftUI presents an animating frame, and the evidence for the fix is a frame capture
/// recorded in the story. What a test *can* pin is the geometry the merged pass draws, which is
/// what these do: a field drawn from the wrong transform, or a mat that does not cover the
/// canvas, would reintroduce a hoop that disagrees with the design by a different route.
@Suite("Stage field geometry")
struct StageFieldTests {
    /// A fractional height on purpose: 256.83 is what iPhone 17's default stage layout measures.
    private static let size = CGSize(width: 370, height: 256.833_333_333_333_3)

    @Test("the mat covers the canvas's whole size")
    func matCoversTheCanvas() {
        let field = StageField.geometry(
            transform: StageTransform(scale: 0.5, translation: ViewPoint(x: 100, y: 80)),
            size: Self.size,
            increasedContrast: false
        )

        #expect(field.mat == CGRect(origin: .zero, size: Self.size))
    }

    /// Worked by hand rather than through `viewRect`, so the expectation cannot share a defect
    /// with the code under test: the box is ±250 stage points, y up, so at scale 0.5 about
    /// (100, 80) it spans x −25…225 and, flipped, y −45…205.
    @Test("the hoop is the box mapped through the transform it is given")
    func hoopFollowsTheTransform() {
        let field = StageField.geometry(
            transform: StageTransform(scale: 0.5, translation: ViewPoint(x: 100, y: 80)),
            size: Self.size,
            increasedContrast: false
        )

        #expect(field.hoop == CGRect(x: -25, y: -45, width: 250, height: 250))
    }

    /// The expectation is computed in the body rather than passed as an argument, because test
    /// arguments are evaluated off the main actor and `StageChrome` is main-actor isolated.
    @MainActor
    @Test("Increase Contrast thickens the hoop outline", arguments: [false, true])
    func outlineWidth(increasedContrast: Bool) {
        let expected = increasedContrast ? 2 : StageChrome.hoopLineWidth
        let field = StageField.geometry(
            transform: StageTransform(scale: 1, translation: .zero),
            size: Self.size,
            increasedContrast: increasedContrast
        )

        #expect(field.outlineWidth == expected)
    }
}
