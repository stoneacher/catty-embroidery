import EditorCore

/// The parameter editor's half of the window state (US-410).
extension AppModel {
    var isParameterEditorPresented: Bool {
        get { false }
        set {}
    }

    func openParameterEditor() {}
}
