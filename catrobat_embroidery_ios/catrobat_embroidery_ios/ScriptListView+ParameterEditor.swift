import SwiftUI

/// US-410, in its own file because `ScriptListView.swift` is at SwiftLint's length limit.
extension ScriptListView {
    /// The bottom bar's Edit button, and the parameter editor's one presentation (US-410,
    /// ADR-039) — `addButton`'s adaptation: a sheet where the width is compact, a popover
    /// anchored to the button elsewhere.
    ///
    /// A tap on a row selects it (ADR-039's 2026-09-30 amendment), so the editor opens from the
    /// selection rather than from the row — nothing interactive goes inside a row (ADR-034).
    ///
    /// **Modal, unlike the palette**: background interaction stays disabled, because a swipe
    /// delete under the sheet would change which brick the open session's address names.
    var editButton: some View {
        @Bindable var model = model

        return Button {
            model.openParameterEditor()
        } label: {
            Label {
                Text(.parameterEditorEdit)
            } icon: {
                Image(systemName: "slider.horizontal.3")
            }
        }
        .disabled(!model.editor.canEditSelectedBrick)
        .popover(isPresented: $model.isParameterEditorPresented, arrowEdge: .bottom) {
            ParameterEditorView(model: model)
                .presentationCompactAdaptation(horizontal: .sheet, vertical: .popover)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                // No `onDisappear` ending the session: Done and a swipe-down both write the
                // binding, and in ADR-023's container swap the old popover's disappearance would
                // end the session the new container is still presenting. The teardown paths
                // that bypass the binding end it themselves (`AppModel`).
        }
    }
}
