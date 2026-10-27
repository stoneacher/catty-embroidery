import SwiftUI

/// The list's Rename (project management slice 9; brief D8): `DesignNameField` in a sheet, with
/// Cancel and a Save that is disabled while the name is invalid.
///
/// **It holds no name.** The text is `AppModel.listState.rename`'s transient buffer, written
/// through on every keystroke, so an invalid value never reaches the program, the list or the
/// history, and an iPad resize that rebuilds the list re-presents the sheet with what was typed
/// (ADR-023). Whether a rename is an edit or a catalog write is `AppModel.commitRename()`'s
/// call; this view only routes Return and the two buttons there.
struct RenameSheet: View {
    let model: AppModel

    /// Owned here because only the declarer of a `@FocusState` can set it: the field is focused
    /// when the sheet appears, and focused again after a rejected Return (D8).
    @FocusState private var isFocused: Bool

    /// Written through `listState.rename`, never a copy. Reading `?? ""` covers the frame in
    /// which the sheet animates away after Save or Cancel has already cleared the session.
    private var text: Binding<String> {
        Binding(
            get: { model.listState.rename?.text ?? "" },
            set: { model.listState.rename?.text = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            if let session = model.listState.rename {
                content(session)
            }
        }
        // Detents apply to the compact sheet only; a regular-width iPad presents a form sheet
        // and ignores them, which is the presentation we want there anyway. One field does not
        // earn a full-height sheet on iPhone.
        .presentationDetents([.medium])
    }

    private func content(_ session: RenameSession) -> some View {
        DesignNameField(name: text, validation: session.validation, isFocused: $isFocused)
            .onSubmit(submit)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle(Text(.projectRenameTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        model.cancelRename()
                    } label: {
                        Text(.projectRenameCancel)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        model.commitRename()
                    } label: {
                        Text(.projectRenameSave)
                    }
                    .disabled(!session.canSave)
                }
            }
            .onAppear {
                isFocused = true
            }
    }

    /// Return saves like Save does. A rejected name leaves the session, and so the typed text,
    /// in place (`commitRename()` returns `false`); but a single-line `TextField` resigns on
    /// Return regardless, so focus is asked back, or the keyboard would vanish under an error
    /// the user is meant to fix (D8: "on submit it keeps focus and shows the error"). Deferred
    /// to the next main-actor turn so it lands after that resignation whatever order UIKit runs
    /// the submit and the resign in, which is not documented. On the iOS 26 simulator
    /// (2026-10-27) a synchronous assignment held too; the deferral costs nothing and does not
    /// rely on that.
    private func submit() {
        guard !model.commitRename() else { return }
        Task { @MainActor in
            isFocused = true
        }
    }
}
