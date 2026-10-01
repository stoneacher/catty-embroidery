import EditorCore
import SwiftUI

/// The working program's first script as a read-only list (US-407).
///
/// **Where it lives is ADR-039**: the middle column of a three-column split on regular width,
/// beside the stage; on compact, the screen a selection opens, with the stage pushed from its
/// toolbar. That gives US-409's palette a defined place to present from — this view's toolbar,
/// in both layouts.
///
/// **Rows hold no control** (ADR-034): they are identified by index, which is safe only while
/// nothing inside a row has state of its own. Since US-408 the list reorders and deletes —
/// `.onMove`, `.onDelete` and each row's accessibility actions — and every one of them is an
/// `EditAction` handed to `model.editor`, never a mutation (ADR-006 pattern 1). Add and
/// parameter editing are US-409 and US-410.
///
/// **No drag needs `EditMode`**: a long press lifts the row (checked on an iOS 26.5 simulator
/// build at planning, 2026-09-29 — **not** on iOS 17, for want of a runtime), so there is no
/// Edit button and no mode. The drag preview is
/// one row even when a loop moves as a block — the iOS 17 `List` path has no multi-row preview
/// — and the body snaps in under its opener on the drop. **Nothing is `withAnimation`-ed**:
/// rows are identified by index, so after a move every id is still present and only contents
/// change, and after a delete the ids that vanish are the *last* ones — an animation would
/// show the bottom rows leaving while a loop in the middle was the one deleted.
///
/// It takes the model rather than the program, so that the body depends on `editor.program`
/// and the selection's title alone. `RootView`'s own body reads the run — once per batch while
/// a design stitches — and a value parameter would hand this view a fresh copy each time.
struct ScriptListView: View {
    /// Where the list sits, decided by the container — the `SamplePickerView.showsSelection`
    /// pattern; this view never reads the size class.
    enum Placement {
        /// Compact: the list is the screen a selection opens, titled with the design's name, and
        /// the stage is a push away from its toolbar.
        case stack
        /// Regular: the middle column. The stage beside it already carries the design's name, so
        /// this column is titled "Script", and a link to the stage would be a button that does
        /// nothing visible.
        case column
    }

    let model: AppModel
    let placement: Placement

    @Environment(\.locale) private var locale

    /// The row VoiceOver is on, by index. Set after an accessibility move so focus follows the
    /// moved brick: with index identity it would otherwise stay on the old index, which now
    /// holds a different brick, and a second "Move Up" would move that one.
    @AccessibilityFocusState private var focusedRow: Int?

    static var emptyStateTitle: String {
        String(localized: .scriptEmptyTitle)
    }

    static var emptyStateDescription: String {
        String(localized: .scriptEmptyDescription)
    }

    var body: some View {
        let rows = BrickRowPresentation.rows(for: model.editor.program, locale: locale)

        Group {
            if rows.isEmpty {
                // Names the action, not a control: US-409 fills the `actions:` slot with an
                // "Add Brick" button, and the copy stays true on both sides of that story.
                ContentUnavailableView {
                    Label {
                        Text(.scriptEmptyTitle)
                    } icon: {
                        Image(systemName: "list.bullet.indent")
                    }
                } description: {
                    Text(.scriptEmptyDescription)
                }
            } else {
                List {
                    ForEach(rows) { row in
                        ScriptRowView(row: row)
                            // On the row's one accessibility element — `ScriptRowView` collapses
                            // itself into one — so VoiceOver reaches them behind the rotor
                            // (ADR-031): "rotate to Actions, then swipe".
                            .accessibilityActions { actions(for: row) }
                            .accessibilityFocused($focusedRow, equals: row.id)
                            // `.onMove` has no reject hook, so refuse up front the drags `apply`
                            // always rejects rather than spring the row back unexplained.
                            .moveDisabled(row.isMoveDisabled)
                            // Zero vertical insets so the nesting guides of adjacent rows meet
                            // into one line; the row re-applies its own vertical padding inside.
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            // The guides are the structure; a separator across them would cut
                            // every loop body into rungs.
                            .listRowSeparator(.hidden)
                    }
                    .onMove { source, toOffset in
                        _ = model.editor.moveRows(fromOffsets: source, toOffset: toOffset)
                    }
                    // No confirmation, even for a whole loop (ADR-035): Undo is one tap away.
                    .onDelete { offsets in
                        _ = model.editor.deleteRows(atOffsets: offsets)
                    }
                }
                .listStyle(.plain)
                // The system's default minimum is taller than a one-line row, so the cell would
                // centre the row inside itself and every guide would stop short of its
                // neighbour's — measured at 51 pt cells around 44 pt rows. The row keeps its own
                // 44 pt floor.
                .environment(\.defaultMinListRowHeight, 44)
            }
        }
        .navigationTitle(Text(title))
        // On the `Group`, outside the empty-state branch: after deleting the last brick, the
        // empty state is exactly where Undo must still be.
        .toolbar {
            // The bottom bar in both placements (decided 2026-09-29): the top bar holds the
            // stage link on compact and gets US-409's Add. No ⌘Z here — US-411's `UndoManager`
            // bridge owns the keyboard, and two registrations would undo twice.
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    model.editor.undo()
                } label: {
                    Label {
                        Text(.scriptUndo)
                    } icon: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                }
                .disabled(!model.editor.canUndo)

                Button {
                    model.editor.redo()
                } label: {
                    Label {
                        Text(.scriptRedo)
                    } icon: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                }
                .disabled(!model.editor.canRedo)
            }
            if placement == .stack {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: StageDestination.stage) {
                        Label {
                            Text(.stageTitle)
                        } icon: {
                            Image(systemName: "play.rectangle")
                        }
                        .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
    }
}

private extension ScriptListView {
    /// The row's accessibility actions, each present only where it can succeed — the row
    /// computes them (`BrickRowPresentation`), so a loop end offers Delete alone.
    @ViewBuilder
    func actions(for row: BrickRowPresentation) -> some View {
        if let action = row.moveUp {
            Button(.scriptActionMoveUp) { perform(action) }
        }
        if let action = row.moveDown {
            Button(.scriptActionMoveDown) { perform(action) }
        }
        if let action = row.moveAboveLoop {
            Button(.scriptActionMoveAboveLoop) { perform(action) }
        }
        if let action = row.moveBelowLoop {
            Button(.scriptActionMoveBelowLoop) { perform(action) }
        }
        if let action = row.moveIntoLoopAbove {
            Button(.scriptActionMoveIntoLoopAbove) { perform(action) }
        }
        if let action = row.moveIntoLoopBelow {
            Button(.scriptActionMoveIntoLoopBelow) { perform(action) }
        }
        if let action = row.delete {
            Button(.scriptActionDelete, role: .destructive) { perform(action) }
        }
    }

    /// Applies an accessibility action and, for a move, puts VoiceOver on the moved brick.
    ///
    /// A `.move`'s destination is an insertion index into the list with the block removed, so
    /// it is exactly the moved block's new first row. Set on the next turn, once the list holds
    /// the new rows. No announcement: moving focus reads the brick's label, which is the
    /// confirmation, and spoken announcements are US-411's.
    func perform(_ action: EditAction) {
        guard case .applied = model.editor.apply(action) else { return }
        if case let .move(_, destination) = action {
            Task { @MainActor in
                focusedRow = destination
            }
        }
    }

    var title: LocalizedStringResource {
        switch placement {
        case .stack: model.selection?.title ?? .scriptTitle
        case .column: .scriptTitle
        }
    }
}

/// One brick: a leading symbol (or the thread's swatch), its sentence, and one guide per loop
/// it sits inside.
///
/// Internal rather than `private` only for previews.
struct ScriptRowView: View {
    let row: BrickRowPresentation

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var swatchSize: CGFloat = 18
    /// One width for every leading symbol and the swatch, so the sentences start on one line.
    @ScaledMetric(relativeTo: .body) private var leadingWidth: CGFloat = 24

    var body: some View {
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize

        HStack(alignment: .firstTextBaseline, spacing: 10) {
            leading
                .frame(width: leadingWidth)
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
    }

    @ViewBuilder
    private var leading: some View {
        if let threadColor = row.threadColor {
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
            Image(systemName: Self.symbol(for: row.kind))
                .font(.body)
                .foregroundStyle(Self.tint(for: row.kind))
        }
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
