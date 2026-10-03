import EditorCore

/// The parameter editor's half of the window state (US-410).
///
/// **No flag of its own**: the editor shows exactly while `editor.parameterSession` is open
/// (ADR-036, ADR-039). The session lives on the editor view model, which `AppModel` owns above
/// `RootView` for ADR-023's reason, so a container swap neither loses it nor leaves a second copy
/// that could disagree. Every teardown path ends the session itself rather than relying on the
/// sheet's `onDisappear`, which a container swap can skip.
extension AppModel {
    /// The sheet's and popover's binding. Writing `false` — Done, a swipe down, a tap outside the
    /// popover — ends the session: one undo entry for everything it changed.
    var isParameterEditorPresented: Bool {
        get { editor.parameterSession != nil }
        set {
            if !newValue {
                editor.endParameterEdit()
            }
        }
    }

    /// The toolbar's Edit button and the row's "Edit Parameters" action: opens the editor on the
    /// selected brick, closing the palette first so two popovers never compete for one toolbar.
    func openParameterEditor() {
        guard let index = editor.selectedBrickIndex else { return }
        palette.isPresented = false
        editor.beginParameterEdit(at: index)
    }

    /// The row's accessibility action: select the row, then open.
    func openParameterEditor(at index: Int) {
        editor.selectedBrickIndex = index
        openParameterEditor()
    }
}
