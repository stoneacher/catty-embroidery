import EditorCore
import ProgramModel
import SwiftUI

/// A numeric slot: a number, or a variable, and the switch between them (US-410).
///
/// The switch is one `replaceBrick` each way (test-first item 7c). Switching to a variable with
/// none declared opens the naming field instead of writing a variable that does not exist.
struct FormulaSlotEditor: View {
    let editor: EditorViewModel
    let slot: ParameterSlot

    @State private var text = ""
    @State private var problem: FormulaLiteralError?
    @State private var isNaming = false
    @FocusState private var isFocused: Bool

    @Environment(\.locale) private var locale

    private var value: ParameterValue? {
        editor.editedBrick?.parameters.first { $0.slot == slot }?.value
    }

    private var number: Double? {
        if case let .formula(.number(number)) = value {
            number
        } else {
            nil
        }
    }

    private var variable: String? {
        if case let .formula(.variable(name)) = value {
            name
        } else {
            nil
        }
    }

    var body: some View {
        Picker(selection: source) {
            Text(.parameterSourceNumber).tag(false)
            Text(.parameterSourceVariable).tag(true)
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(Text(ParameterEditorText.title(of: slot, locale: locale)))

        if variable != nil || isNaming {
            VariableChooser(editor: editor, slot: slot, isNaming: $isNaming)
        } else {
            numberField
        }
    }

    /// `true` for a variable. Writing `true` with nothing to choose opens the naming field;
    /// `false` restores a number (`switchToNumber`).
    private var source: Binding<Bool> {
        Binding {
            variable != nil || isNaming
        } set: { toVariable in
            if toVariable {
                if let first = editor.variableMenu.names.first {
                    editor.useVariable(named: first, for: slot)
                } else {
                    isNaming = true
                }
            } else {
                isNaming = false
                editor.switchToNumber(slot)
                syncText()
            }
        }
    }

    @ViewBuilder
    private var numberField: some View {
        HStack {
            TextField(text: $text) {
                Text(ParameterEditorText.title(of: slot, locale: locale))
            }
            // Not `.decimalPad`: it has no minus key on iPhone, and the templates use negatives.
            .keyboardType(.numbersAndPunctuation)
            .autocorrectionDisabled()
            .monospacedDigit()
            .frame(minHeight: RunControl.minimumTouchTarget)
            // A `Form` row's `TextField` label is not used as its accessibility label — the
            // simulator's snapshot showed the field unlabelled — so it is stated outright.
            .accessibilityLabel(Text(ParameterEditorText.title(of: slot, locale: locale)))
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused {
                    // A typing run starts: a rejected entry will return the slot here.
                    editor.beginNumberEntry(for: slot)
                } else if problem != nil {
                    // Leaving a rejected entry shows the value the brick actually holds.
                    syncText()
                }
            }
            .onChange(of: text) { _, newText in
                let rejected = editor.enterNumber(newText, for: slot)
                if rejected != problem {
                    problem = rejected
                    if let rejected {
                        AccessibilityNotification.Announcement(ParameterEditorText.message(for: rejected)).post()
                    }
                }
            }

            // Only while the text is a number: stepping from a rejected entry would step the
            // last valid value and silently discard what is in the field.
            if problem == nil {
                Stepper {
                    Text(ParameterEditorText.title(of: slot, locale: locale))
                } onIncrement: {
                    editor.stepNumber(slot, by: 1)
                    syncText()
                } onDecrement: {
                    editor.stepNumber(slot, by: -1)
                    syncText()
                }
                .labelsHidden()
            }
        }
        .onAppear(perform: syncText)

        if let problem {
            ProblemLine(message: ParameterEditorText.message(for: problem))
        }
    }

    private func syncText() {
        guard let number else { return }
        text = NumberFieldText.text(for: number, decimalSeparator: editor.decimalSeparator)
        problem = nil
    }
}

/// Which variable a slot uses: the menu of what the object can reference, object scope first,
/// and a field to name a new one (declare on use, ADR-035 amendment).
///
/// Serves both a formula slot (as `.variable(name)`) and a `setVariable`/`changeVariableBy`
/// target. A new name is committed by **Create**, never per keystroke — under declare-on-use,
/// typing "Side" live would declare "S", "Si" and "Sid".
struct VariableChooser: View {
    let editor: EditorViewModel
    let slot: ParameterSlot
    @Binding var isNaming: Bool

    @State private var newName = ""
    @State private var problem: VariableNameProblem?

    init(editor: EditorViewModel, slot: ParameterSlot, isNaming: Binding<Bool> = .constant(false)) {
        self.editor = editor
        self.slot = slot
        _isNaming = isNaming
    }

    private var current: String? {
        switch editor.editedBrick?.parameters.first(where: { $0.slot == slot })?.value {
        case let .formula(.variable(name)), let .variableName(name): name
        default: nil
        }
    }

    var body: some View {
        let menu = editor.variableMenu

        if menu.names.isEmpty {
            Text(.parameterVariableNone)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Picker(selection: selection) {
                // A name that resolves nowhere — the template's empty one, or a reference to a
                // variable that was never declared — is shown as it is rather than dropped, so
                // the picker never claims a choice the brick does not hold.
                if let current, menu.scope(of: current) == nil {
                    Text(current.isEmpty ? String(localized: .scriptVariablePlaceholder) : current)
                        .tag(current)
                }
                Section {
                    ForEach(menu.objectVariables, id: \.self) { Text($0).tag($0) }
                } header: {
                    Text(.parameterVariableSectionObject)
                }
                if !menu.projectVariables.isEmpty {
                    Section {
                        ForEach(menu.projectVariables, id: \.self) { Text($0).tag($0) }
                    } header: {
                        Text(.parameterVariableSectionProject)
                    }
                }
            } label: {
                Text(.parameterSlotVariable)
            }
            .pickerStyle(.menu)
        }

        TextField(text: $newName, prompt: Text(.parameterNamePrompt)) {
            Text(.parameterVariableNew)
        }
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .submitLabel(.done)
        .onSubmit(create)
        .frame(minHeight: RunControl.minimumTouchTarget)

        Button(.parameterVariableCreate, action: create)
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)

        if let problem {
            ProblemLine(message: ParameterEditorText.message(for: problem))
        }
    }

    private var selection: Binding<String> {
        Binding {
            current ?? ""
        } set: { name in
            editor.useVariable(named: name, for: slot)
        }
    }

    private func create() {
        switch editor.useVariable(named: newName, for: slot) {
        case let .rejected(.invalidVariableName(rejected)):
            problem = rejected
            AccessibilityNotification.Announcement(ParameterEditorText.message(for: rejected)).post()
        case .applied:
            newName = ""
            problem = nil
            isNaming = false
        case .rejected, nil:
            break
        }
    }
}

/// `writeEmbroideryToFile`'s name, applied live and trimmed. Live is safe here, unlike a
/// variable name: a file name declares nothing, and the session folds the keystrokes into one
/// undo entry. An empty field writes nothing (`setFileName`).
struct FileNameField: View {
    let editor: EditorViewModel
    @State private var name: String

    init(editor: EditorViewModel, initialName: String) {
        self.editor = editor
        _name = State(initialValue: initialName)
    }

    var body: some View {
        TextField(text: $name) {
            Text(.parameterSlotFile)
        }
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .submitLabel(.done)
        .frame(minHeight: RunControl.minimumTouchTarget)
        .onChange(of: name) { _, newName in
            editor.setFileName(newName)
        }
    }
}

/// A formula M4 cannot edit, shown exactly as stored with the reason it is locked — a disabled
/// control with no explanation reads as a bug. Nothing here writes, so the tree stays
/// byte-identical (test-first item 9).
struct ReadOnlyFormulaRow: View {
    let formula: Formula
    let reason: ReadOnlyFormulaReason

    @Environment(\.locale) private var locale

    var body: some View {
        Text(FormulaText.text(for: formula, locale: locale))
            .font(.body.monospacedDigit())
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        Label {
            Text(ParameterEditorText.message(for: reason, locale: locale))
        } icon: {
            Image(systemName: "lock")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// What is wrong with an entry, in `DesignNameField.problemLine`'s style: system red, an icon so
/// colour is not the only signal, and wrapping rather than truncating.
struct ProblemLine: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.circle")
        }
        .font(.footnote)
        .foregroundStyle(.red)
        .fixedSize(horizontal: false, vertical: true)
    }
}
