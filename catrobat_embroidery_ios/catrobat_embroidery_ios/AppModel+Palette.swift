import EditorCore

/// The brick palette's half of the window state (US-409).
///
/// In its own file because `AppModel.swift` is at SwiftLint's length limit. The state itself
/// is `AppModel.palette`, stored above `RootView` for ADR-023's reason. These accessors keep
/// the call sites reading as the model's own properties.
extension AppModel {
    /// Whether the brick palette is showing.
    ///
    /// The palette opens no undo session: an insert is one discrete entry, so nothing can be
    /// left half-coalesced if the presentation goes away. It is closed by every writer of the
    /// selection (`select(_:)`, `restoreSavedProgram()`), by a path that leaves the script, and
    /// by a palette tap that inserted.
    var isPalettePresented: Bool {
        get { palette.isPresented }
        set { palette.isPresented = newValue }
    }

    /// The last palette insertion, which the script list scrolls to.
    var paletteInsertion: PaletteInsertion? {
        palette.insertion
    }

    /// A palette row was tapped: insert through the editor's one door, then close the palette
    /// and ask the list to show the new brick.
    ///
    /// A refused insert leaves the palette open and asks for no scroll. Only a program with no
    /// script can refuse a palette kind, since `.loopEnd` is not in the palette, and closing on
    /// it would read as if something had been added.
    func addFromPalette(_ kind: BrickKind) {
        guard let index = editor.insert(kind) else { return }
        palette.inserted(at: index)
    }

    /// `RootView` swapped its navigation container (ADR-023).
    ///
    /// On compact the palette is presented from the script's toolbar, so it can only be showing
    /// while the script is on top. `path`'s own hook covers every *write* of the path, but this
    /// is the case no write covers: the stage was pushed on compact, the window went regular
    /// (the split ignores `path`), the palette was opened from the script column, and the
    /// window went compact again with the stage on top. Left `true`, the flag would either
    /// present the palette over the stage or make the next Add tap change nothing
    /// (`swift-code-reviewer`, US-409).
    func layoutChanged(isCompact: Bool) {
        if isCompact, path.last != .script {
            palette.isPresented = false
        }
    }
}
