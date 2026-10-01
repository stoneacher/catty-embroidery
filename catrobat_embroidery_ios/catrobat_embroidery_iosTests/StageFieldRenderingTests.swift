@testable import catrobat_embroidery_ios
import EmbroideryEngine
import StagePreview
import SwiftUI
import Testing

/// The renderer's one pass, rendered: the field is drawn, beneath the design, at `current`.
///
/// **Added after `swift-code-reviewer`'s mutation pass on US-315.** `StageFieldTests` pins the
/// geometry the field is drawn *as*, and three mutants of the merged pass survived it all the
/// same: deleting the `StageField.draw` call, drawing the field after the strokes (covering the
/// design), and drawing it at `bake` instead of `current`. The last is the fix's whole point,
/// because one pass only cannot disagree with itself if both halves read the same transform.
/// `ImageRenderer` hosts the real `CanvasStitchRenderer`, so three pixels can tell those apart —
/// each mutant was applied and is killed by at least one test here.
///
/// What this still cannot see is the defect US-315 was about, which exists only while SwiftUI
/// animates a frame. The frame capture in `docs/screenshots/us-315/` is the evidence for that.
@MainActor
@Suite("Stage field rendering")
struct StageFieldRenderingTests {
    private static let side = 600.0

    /// `bake` and `current` differ on purpose, so that a field drawn at the wrong one lands
    /// somewhere else. At `current` the hoop spans view 50…550; at `bake` it spans −25…225.
    private static let transform = StageRenderTransform.live(
        bake: StageTransform(scale: 0.5, translation: ViewPoint(x: 100, y: 100)),
        current: StageTransform(scale: 1, translation: ViewPoint(x: 300, y: 300))
    )

    private static let thread = ThreadColor(red: 200, green: 0, blue: 0)

    /// Two stitches either side of the stage origin. At `current` their penetration dots land on
    /// view (200, 300) and (400, 300), both inside the hoop. The probe reads the dot rather than
    /// the span between them, because the dot is what is drawn in the thread's own colour at a
    /// point a test can name exactly (measured: the span is not red at this scale).
    private static func display() -> StitchDisplayList {
        var list = StitchDisplayList()
        list.append(contentsOf: [
            PreviewStitch(position: StagePoint(x: -100, y: 0), color: thread),
            PreviewStitch(position: StagePoint(x: 100, y: 0), color: thread)
        ])
        return list
    }

    /// One 8-bit sRGB pixel.
    private struct RGB: CustomStringConvertible {
        let red: Int
        let green: Int
        let blue: Int

        var description: String { "(\(red), \(green), \(blue))" }

        /// Within a few levels, for the colour-space round trip.
        func matches(_ other: RGB) -> Bool {
            abs(red - other.red) <= 4 && abs(green - other.green) <= 4 && abs(blue - other.blue) <= 4
        }
    }

    /// The rendered frame as 8-bit sRGB, read back pixel by pixel.
    private struct Frame {
        let bytes: [UInt8]
        let width: Int

        func rgb(atX x: Int, y: Int) -> RGB {
            let offset = (y * width + x) * 4
            return RGB(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]))
        }
    }

    private static func render() throws -> Frame {
        let view = CanvasStitchRenderer()
            .makeBody(
                display: display(),
                transform: transform,
                needle: nil,
                viewport: ViewSize(width: side, height: side)
            )
            .frame(width: side, height: side)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)

        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // CoreGraphics' origin is bottom-left; flip so rows read top-down like view points.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn)
        return Frame(bytes: bytes, width: width)
    }

    @Test("inside the hoop at `current`, and outside it at `bake`, the frame shows the hoop field")
    func fieldIsDrawnAtCurrent() throws {
        let pixel = try Self.render().rgb(atX: 450, y: 450)
        #expect(pixel.matches(RGB(red: 218, green: 215, blue: 208)), "got \(pixel)")
    }

    /// Kills the deleted-draw mutant. It does **not** discriminate a field drawn at `bake`, although
    /// (20, 20) lies inside the `bake` hoop: measured, that mutant still left the mat here, and only
    /// `fieldIsDrawnAtCurrent` caught it. The claim is left at what was measured.
    @Test("outside the hoop the frame shows the mat")
    func matIsDrawnAtCurrent() throws {
        let pixel = try Self.render().rgb(atX: 20, y: 20)
        #expect(pixel.matches(RGB(red: 190, green: 186, blue: 178)), "got \(pixel)")
    }

    @Test("the design is drawn over the field, not under it")
    func designIsOnTop() throws {
        let pixel = try Self.render().rgb(atX: 200, y: 300)
        #expect(pixel.matches(RGB(red: 200, green: 0, blue: 0)), "got \(pixel)")
    }
}
