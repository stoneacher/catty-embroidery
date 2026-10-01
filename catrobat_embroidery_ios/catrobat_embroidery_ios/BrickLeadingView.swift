import EditorCore
import EmbroideryEngine
import SwiftUI

/// A brick's leading mark: its category's symbol, or the thread's swatch for a brick that sets
/// one (US-407; shared since US-409).
///
/// **One view for the script row and the palette row**, so the two cannot drift. The palette's
/// criterion is that each row shows "the brick as it will appear", and a symbol or tint
/// changed in one place but not the other would make the palette promise a brick the script
/// does not show.
///
/// It owns its width, so every sentence beside it — in either list — starts on one line.
/// Decoration only: both rows collapse into one VoiceOver element whose label carries the
/// meaning, so nothing here is spoken.
struct BrickLeadingView: View {
    let kind: BrickKind
    let threadColor: ThreadColor?

    @ScaledMetric(relativeTo: .body) private var swatchSize: CGFloat = 18
    /// One width for every leading symbol and the swatch, so the sentences start on one line.
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 24

    var body: some View {
        mark
            .frame(width: width)
    }

    @ViewBuilder
    private var mark: some View {
        if let threadColor {
            // Design data: `Color(threadColor)` never adapts to dark mode. The ring is chrome,
            // and is what keeps a white thread visible on a white row and a black one on black.
            Circle()
                .fill(Color(threadColor))
                .overlay(Circle().strokeBorder(.separator, lineWidth: 1))
                .frame(width: swatchSize, height: swatchSize)
                // A circle has no baseline; sitting its lower fifth on the text's first baseline
                // centres it on the first line's x-height, as a symbol would be.
                .alignmentGuide(.firstTextBaseline) { $0.height * 0.8 }
        } else {
            Image(systemName: Self.symbol(for: kind))
                .font(.body)
                .foregroundStyle(Self.tint(for: kind))
        }
    }

    /// One symbol per category, so category never rests on colour alone; the control bricks
    /// that are not loops get their own, because "wait" is not a loop.
    private static func symbol(for kind: BrickKind) -> String {
        switch kind {
        case .moveNSteps, .turnLeft, .turnRight, .pointInDirection, .placeAt, .setX, .setY,
             .changeXBy, .changeYBy:
            "arrow.up.and.down.and.arrow.left.and.right"
        case .repeatLoop: "repeat"
        case .forever: "infinity"
        case .loopEnd: "arrow.uturn.backward"
        case .wait: "clock"
        case .setVariable, .changeVariableBy: "x.squareroot"
        case .stitch, .setThreadColor, .runningStitch, .zigZagStitch, .tripleStitch, .sewUp,
             .stopRunningStitch, .writeEmbroideryToFile:
            "scissors"
        }
    }

    /// Chrome, not design data: system colours, which adapt to dark mode and Increase Contrast.
    private static func tint(for kind: BrickKind) -> Color {
        switch kind {
        case .moveNSteps, .turnLeft, .turnRight, .pointInDirection, .placeAt, .setX, .setY,
             .changeXBy, .changeYBy:
            .blue
        case .repeatLoop, .forever, .loopEnd, .wait: .orange
        case .setVariable, .changeVariableBy: .red
        case .stitch, .setThreadColor, .runningStitch, .zigZagStitch, .tripleStitch, .sewUp,
             .stopRunningStitch, .writeEmbroideryToFile:
            .purple
        }
    }
}
