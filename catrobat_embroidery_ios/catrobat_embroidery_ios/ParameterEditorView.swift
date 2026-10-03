import EditorCore
import ProgramModel
import SwiftUI

/// The off-row parameter editor (US-410, ADR-039): one section per slot of the selected brick,
/// each with the control its value calls for.
///
/// **It presents nothing itself**, like `PaletteView`: `ScriptListView`'s Edit button owns the
/// one presentation — a popover on regular, a sheet on compact — and the presentation's
/// lifetime is the editor's undo session (`AppModel.isParameterEditorPresented`). Every control
/// applies **live** through the editor view model, so there is no Cancel: Undo reverses the
/// whole session in one step (ADR-036).
struct ParameterEditorView: View {
    let model: AppModel

    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            Form {
                if let brick = model.editor.editedBrick {
                    Section {
                        // The brick as the row reads it, so the user can see what they are
                        // changing without looking past the sheet.
                        Text(BrickRowPresentation.text(of: brick, locale: locale))
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(brick.parameters, id: \.slot) { parameter in
                        Section {
                            editor(for: parameter)
                        } header: {
                            Text(ParameterEditorText.title(of: parameter.slot, locale: locale))
                        }
                    }
                }
            }
            // The slot editors hold `@State` (the field's text, the file name) seeded from the
            // brick. A new session — a different brick under the same presentation — must start
            // them fresh rather than show the last brick's text (`swift-code-reviewer`, US-410).
            .id(model.editor.parameterSession?.key)
            .navigationTitle(Text(.parameterEditorTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.parameterEditorDone) {
                        model.isParameterEditorPresented = false
                    }
                }
            }
        }
        // `PaletteView`'s sizing: ideal sizes for the popover, no minimum height for the sheet.
        .frame(minWidth: 320, idealWidth: 380, idealHeight: 520)
    }

    @ViewBuilder
    private func editor(for parameter: BrickParameter) -> some View {
        switch ParameterEditorKind(parameter.value) {
        case .number, .variableReference:
            FormulaSlotEditor(editor: model.editor, slot: parameter.slot)
        case let .readOnlyFormula(formula, reason):
            ReadOnlyFormulaRow(formula: formula, reason: reason)
        case .variableName:
            VariableChooser(editor: model.editor, slot: parameter.slot)
        case let .threadColor(hex):
            ThreadPaletteGrid(selectedHex: hex) { swatch in
                model.editor.setParameter(.hex, to: .threadColor(hex: swatch.hex))
            }
        case let .fileName(name):
            FileNameField(editor: model.editor, initialName: name)
        }
    }
}
