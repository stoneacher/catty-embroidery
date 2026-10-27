import Projects
import Samples
import SwiftUI

/// The user's designs, then the examples to start one from (project management slice 7;
/// brief, UI plan of 2026-10-27). It replaced `SamplePickerView` at both of `RootView`'s
/// call sites: the compact stack's root and the regular split's sidebar.
///
/// **It owns no navigation container and never reads the size class.** That is the mechanism
/// by which `RootView`'s container swap loses nothing (ADR-023): the same view is what both
/// containers render, so nothing has to survive the swap by luck.
///
/// What it shows is decided by `ProjectListPresentation`, which is tested; this view only
/// lays the result out and forwards taps to `AppModel`.
struct ProjectListView: View {
    let model: AppModel

    /// Whether the open project's row should *read* as selected.
    ///
    /// True only where the selection is visible next to the list — the split view's sidebar,
    /// where the columns beside it show that design. In the compact stack it is false, because
    /// opening pushes the script and coming back leaves nothing on screen for a highlight to
    /// refer to; a row that stays lit after Back claims a state the screen is not in (reported
    /// from the simulator by Sebastian, 2026-08-12, for the sample picker).
    ///
    /// **A flag, not a size-class read, and that is the point**: the container knows whether it
    /// shows the selection beside the list; this view must not start branching on the
    /// environment. `AppModel.projectID` outlives the pop either way; only its presentation is
    /// conditional.
    let showsSelection: Bool

    var body: some View {
        // Ticks once a minute so "Edited 1 minute ago" does not go stale on a list left open,
        // while each render still reads `now` once — every row agrees, and VoiceOver hears a
        // label change at most once a minute rather than `Text(_:style: .relative)`'s ticking.
        TimelineView(.everyMinute) { context in
            List {
                myDesigns(now: context.date)
                examples
            }
        }
        // Both containers set the same title on this view, so it belongs here rather than
        // being spelled twice in `RootView`'s branches, where the two copies could drift.
        .navigationTitle(Text(.rootTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.newDesign()
                } label: {
                    // The icon in the bar; the title is what VoiceOver and Voice Control use.
                    Label {
                        Text(.projectListNew)
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        // One dialog for the list, not one per row (D9), driven by `AppModel.listState` so an
        // iPad resize that rebuilds this view re-presents it rather than losing it (ADR-023).
        // The binding's setter clears the request on any dismissal; after Delete it finds
        // nothing left to clear, because SwiftUI runs a dialog's action *before* dismissing
        // ("All actions in a confirmation dialog will dismiss the dialog after the action
        // runs"), so `confirmDeletion()` runs once and sees the request.
        .confirmationDialog(
            Text(.projectDeleteTitle(model.listState.pendingDeletion?.name ?? "")),
            isPresented: Binding(
                get: { model.listState.pendingDeletion != nil },
                set: {
                    if !$0 {
                        model.cancelDeletion()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                model.confirmDeletion()
            } label: {
                Text(.projectActionDelete)
            }
            // No Cancel button of our own: the dialog supplies its standard one, in the system
            // language, which is what the launch alert's empty actions rely on too.
        } message: {
            Text(.projectDeleteMessage)
        }
        .alert(
            Text(model.listState.notice?.title ?? ""),
            isPresented: Binding(
                get: { model.listState.notice != nil },
                set: {
                    if !$0 {
                        model.dismissListNotice()
                    }
                }
            ),
            presenting: model.listState.notice,
            // Empty on purpose, as for the launch alert: the system supplies OK, and dismissing
            // by it goes through the setter above.
            actions: { _ in },
            message: { Text($0.message) }
        )
    }

    /// "My Designs": the project rows, or the empty state *inside* the section, so the
    /// examples below stay reachable either way (decided 2026-10-27). Emptiness is the
    /// presentation's call, from the project files alone.
    private func myDesigns(now: Date) -> some View {
        Section {
            switch ProjectListPresentation.content(
                files: model.library.files,
                openID: model.projectID,
                showsSelection: showsSelection
            ) {
            case .empty:
                ContentUnavailableView {
                    Label {
                        Text(.projectListEmptyTitle)
                    } icon: {
                        Image(systemName: "square.stack")
                    }
                } description: {
                    Text(.projectListEmptyDescription)
                }
            case let .rows(rows):
                ForEach(rows) { row in
                    let heldElsewhere = model.isHeldElsewhere(row.id)
                    ProjectRowView(row: row, now: now, heldElsewhere: heldElsewhere) {
                        model.openProject(row.id)
                    }
                    .projectRowActions(
                        ProjectActions.states(for: row, heldElsewhere: heldElsewhere),
                        onDuplicate: { model.duplicate(row.id) },
                        onDelete: { model.requestDeletion(of: row) }
                    )
                }
            }
        } header: {
            Text(.projectListSectionMine)
        }
    }

    /// The bundled samples, in `AppModel.samples`' order (the DEBUG synthetic last). A picked
    /// sample is a draft, not a row, so these never show a selection.
    ///
    /// A `Button`, **not** `List(selection:)`, here and in `ProjectRowView`, and this is the
    /// list's load-bearing UI decision. `List(selection:)` gives the sidebar highlight for
    /// free, but not a guarantee that tapping the **already-selected** row writes the binding
    /// again — undocumented, collection-view-backed behaviour, not an API contract. Re-tapping
    /// must still reach the model: re-selecting a sample re-publishes it (US-304), and tapping
    /// the open project shows its script. The costs are paid where they arise: the tint is
    /// hand-rolled, `PickerRowButtonStyle` restores the pressed state `.plain` drops, and
    /// zeroed `listRowInsets` make the whole row the hit area. `.onTapGesture` was the other
    /// way out and is worse: it competes with the list's own tap handling and breaks keyboard
    /// selection.
    private var examples: some View {
        Section {
            ForEach(model.samples) { sample in
                Button {
                    model.select(sample)
                } label: {
                    SampleRowView(sample: sample, isSelected: false)
                }
                .buttonStyle(PickerRowButtonStyle())
                .listRowInsets(EdgeInsets())
            }
        } header: {
            Text(.rootSamplesHeader)
        }
    }
}

// The project rows depend on the files in the preview library's scratch directory, so these
// show whatever is there — usually the empty state. The refused-row and populated layouts are
// covered by the simulator screenshots the UI definition of done requires.
#Preview("In the stack") {
    NavigationStack {
        ProjectListView(model: AppModel(library: .preview), showsSelection: false)
    }
}

#Preview("As a sidebar") {
    NavigationStack {
        ProjectListView(model: AppModel(library: .preview), showsSelection: true)
    }
}
