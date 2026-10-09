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
/// `EditAction` handed to `model.editor`, never a mutation (ADR-006 pattern 1). Parameter
/// editing is US-410.
///
/// **Selection is `List`'s own** (US-409), bound to `editor.selectedBrickIndex`, which is where
/// a palette tap inserts. It is still no control inside a row: the cell is what selects, and
/// the index it writes is cleared by the editor on every change that can move rows, so index
/// identity never leaves it pointing at a different brick.
///
/// **The palette presents from here, once**: the top bar's Add button in both placements owns
/// the one `.popover`, which adapts to a detented sheet on compact (ADR-039). The empty
/// state's button only raises `isPalettePresented`, so there is one call site to keep right.
/// While the sheet is up, the list's bottom content margin grows by what the sheet covers
/// (`bottomInset(listFrame:paletteFrame:)`), because SwiftUI insets a list for the keyboard
/// but not for a sheet, and a freshly inserted brick would otherwise land behind it.
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

    /// The list's frame in window coordinates, for the sheet overlap.
    @State private var listFrame: CGRect = .zero

    /// The presented palette's frame in window coordinates, `nil` while it is not showing.
    /// View state rather than model state on purpose: it is a measurement, re-reported by the
    /// palette after ADR-023's container swap, not something that must survive one.
    @State private var paletteFrame: CGRect?

    /// The inserted row VoiceOver moves to once the palette has gone (see the `onChange`).
    @State private var pendingFocus: Int?

    static var emptyStateTitle: String {
        String(localized: .scriptEmptyTitle)
    }

    static var emptyStateDescription: String {
        String(localized: .scriptEmptyDescription)
    }

    var body: some View {
        let rows = BrickRowPresentation.rows(for: model.editor.program, locale: locale)
        @Bindable var editor = model.editor

        // Around the `Group`, not the `List`: the first insert into an empty script is the one
        // that brings the list into existence, and an `onChange` on the list itself would not
        // be there yet to see it.
        ScrollViewReader { proxy in
            Group {
                if rows.isEmpty {
                    // The description names the action rather than this button, so the copy
                    // reads the same with or without it (it predates the button, US-407).
                    ContentUnavailableView {
                        Label {
                            Text(.scriptEmptyTitle)
                        } icon: {
                            Image(systemName: "list.bullet.indent")
                        }
                    } description: {
                        Text(.scriptEmptyDescription)
                    } actions: {
                        // Raises the flag only; the toolbar's Add button owns the presentation,
                        // so popover-versus-sheet is decided in one place.
                        Button {
                            model.isPalettePresented = true
                        } label: {
                            Label {
                                Text(.scriptAdd)
                            } icon: {
                                Image(systemName: "plus")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    list(rows: rows, selection: $editor.selectedBrickIndex)
                }
            }
            .onChange(of: model.paletteInsertion) { _, insertion in
                guard let insertion else { return }
                // On the next turn, once the list holds the inserted rows — `perform(_:)`'s
                // reason. Not animated: the palette's dismissal is already moving the screen.
                Task { @MainActor in
                    proxy.scrollTo(insertion.index, anchor: nil)
                }
                // VoiceOver focus waits for the palette to finish leaving. When a presentation
                // finishes dismissing, UIKit hands focus back to the button that presented it,
                // which would overwrite a focus set now (`swift-code-reviewer`, US-409). The
                // user would land on Add with no idea where the brick went.
                pendingFocus = insertion.index
            }
        }
        // Behind both the list and its empty state: the first responder that hands shake, ⌘Z
        // and the edit menu the editor's own history (US-411). Undo matters most right after the
        // last brick is deleted.
        .background(UndoResponderAnchor(manager: model.editor.systemUndoManager))
        .navigationTitle(Text(title))
        // Outside the empty-state branch: after deleting the last brick, the empty state is
        // exactly where Undo must still be — and where Add is the only way forward.
        .toolbar {
            // The bottom bar in both placements (decided 2026-09-29): the top bar holds the
            // stage link on compact and Add in both. No ⌘Z shortcut on these buttons: the system's
            // ⌘Z reaches the same history through `UndoResponderAnchor` (US-411), and two
            // registrations would undo twice.
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

                Spacer()

                editButton
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
            ToolbarItem(placement: .primaryAction) {
                addButton
            }
        }
    }

    /// How much of the list's bottom a presented palette covers, which is the bottom content
    /// margin that keeps every row — above all a freshly inserted one — scrollable into view.
    ///
    /// **Zero for a popover, by geometry rather than by size class**: a sheet rises from the
    /// window's bottom edge, so its frame always reaches the list's bottom; a popover hangs
    /// from its toolbar button and stops short of it. Asking the frames keeps this view off
    /// the size class (`Placement`'s rule), and stays right in the configurations where the
    /// adaptation is the system's call — regular width with compact height, a short iPad
    /// window — because it measures what was presented instead of predicting it.
    ///
    /// Clamped to the list's height: at the large detent the sheet covers the whole list, and
    /// a margin taller than the list scrolls nothing further into view.
    nonisolated static func bottomInset(listFrame: CGRect, paletteFrame: CGRect?) -> CGFloat {
        guard let paletteFrame,
              paletteFrame.maxY >= listFrame.maxY,
              paletteFrame.minX < listFrame.maxX,
              paletteFrame.maxX > listFrame.minX
        else { return 0 }
        return min(max(0, listFrame.maxY - paletteFrame.minY), listFrame.height)
    }
}

private extension ScriptListView {
    func list(rows: [BrickRowPresentation], selection: Binding<Int?>) -> some View {
        List(selection: selection) {
            ForEach(rows) { row in
                ScriptRowView(row: row, isSelected: row.id == selection.wrappedValue)
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
        // A content margin rather than a safe-area inset: it moves where scrolling can bring
        // a row, and leaves the list's background running under the sheet.
        .contentMargins(
            .bottom,
            Self.bottomInset(listFrame: listFrame, paletteFrame: paletteFrame),
            for: .scrollContent
        )
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            listFrame = frame
        }
    }

    /// The top bar's Add button, and the palette's one presentation (ADR-039).
    ///
    /// Anchored to the button so the popover's arrow points at what opened it. The two-argument
    /// adaptation asks for a sheet only where the *width* is compact: regular width with
    /// compact height (a large iPhone in landscape, a short iPad window) keeps a popover, which
    /// leaves the script beside it rather than under a sheet covering most of a short screen.
    /// Which adaptation wins where both are compact is the system's; `bottomInset` measures the
    /// result rather than assuming it.
    var addButton: some View {
        @Bindable var model = model

        return Button {
            model.isPalettePresented = true
        } label: {
            Label {
                Text(.scriptAdd)
            } icon: {
                Image(systemName: "plus")
            }
        }
        .popover(isPresented: $model.isPalettePresented, arrowEdge: .top) {
            PaletteView(model: model)
                .presentationCompactAdaptation(horizontal: .sheet, vertical: .popover)
                // `.fraction` rather than `.medium`: the small detent leaves most of the script
                // in view, and its height is a proportion this view does not have to predict —
                // the inset measures the sheet anyway (US-409's constraints).
                .presentationDetents([.fraction(0.4), .large])
                // Mandatory, not a nicety: tap-to-add only makes sense if the script behind
                // the sheet stays live — to select where the next brick goes — while it is up.
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.4)))
                // A swipe in the palette scrolls its list rather than resizing the sheet;
                // the grabber is what resizes.
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
                .onGeometryChange(for: CGRect.self) { proxy in
                    // Extended by the bottom safe area, so the sheet's measured bottom is the
                    // window's and the sheet test in `bottomInset` does not depend on whether
                    // the content is laid out above the home indicator.
                    var frame = proxy.frame(in: .global)
                    frame.size.height += proxy.safeAreaInsets.bottom
                    return frame
                } action: { frame in
                    paletteFrame = frame
                }
                .onDisappear {
                    paletteFrame = nil
                    if let pendingFocus {
                        self.pendingFocus = nil
                        // One more turn, so this lands after the system's own hand-back.
                        Task { @MainActor in
                            focusedRow = pendingFocus
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
        // US-410: the same editor the toolbar opens, reachable without first selecting the row.
        // Not while the palette is up: opening would dismiss one sheet and present another in
        // one update, which UIKit may refuse — leaving a session open with nothing shown.
        if model.editor.hasParameters(at: row.id), !model.isPalettePresented {
            Button(.parameterEditorActionEdit) { model.openParameterEditor(at: row.id) }
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
