import EditorCore
import SwiftUI

/// One brick: its leading mark (`BrickLeadingView`), its sentence, and one guide per loop
/// it sits inside.
///
/// Internal rather than `private` only for previews.
struct ScriptRowView: View {
    let row: BrickRowPresentation
    /// Whether `List` has this row selected. Passed in because the row's one accessibility
    /// element replaces the cell's own, which is where the list's selected state would show.
    var isSelected = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize

        HStack(alignment: .firstTextBaseline, spacing: 10) {
            BrickLeadingView(kind: row.kind, threadColor: row.threadColor)
            Text(row.text)
                .font(.body)
                // A loop's end is structure rather than an instruction; secondary keeps the eye
                // on the bricks that do something, and the sentence still says which loop.
                .foregroundStyle(row.kind == .loopEnd ? .secondary : .primary)
                // What actually guarantees no truncation at AX1 inside a list row — see the
                // same line in `SampleRowView`.
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11)
        .padding(.leading, ScriptRowLayout.indent(forDepth: row.depth, isAccessibilitySize: isAccessibilitySize))
        // A floor for the thumb, not a size — see `SampleRowView`. `maxHeight: .infinity` so the
        // row fills its cell and the guides behind it reach the cell's edges.
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            guides(isAccessibilitySize: isAccessibilitySize)
        }
        // One element per row, with a label a test can read (`BrickRowPresentationTests`); the
        // symbol and the guides are decoration, and the depth is in the label.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.accessibilityLabel))
        // A trait, never words in the label — `SampleRowView`'s reason.
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func guides(isAccessibilitySize: Bool) -> some View {
        ZStack(alignment: .leading) {
            let offsets = ScriptRowLayout.guideOffsets(forDepth: row.depth, isAccessibilitySize: isAccessibilitySize)
            ForEach(offsets.indices, id: \.self) { level in
                // Leading padding rather than `.offset(x:)`, which does not mirror: in a
                // right-to-left layout the guides must follow the indentation to the right.
                Rectangle()
                    .fill(.separator)
                    .frame(width: 2)
                    .padding(.leading, offsets[level] - 1)
            }
        }
        .frame(maxHeight: .infinity)
    }

}
