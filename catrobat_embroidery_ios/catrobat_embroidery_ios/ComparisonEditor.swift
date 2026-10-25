import EditorCore
import ProgramModel
import SwiftUI

/// A condition that is one comparison of two plain values (Variables slice 7, brief D16): three
/// sections in reading order — first value, comparison, second value — as the row reads
/// "If Counter < 10 is true then". Each side is the slot editor's own number/variable control,
/// addressed to that side, so every edit joins the one parameter session (ADR-036).
struct ComparisonEditor: View {
    let editor: EditorViewModel
    let slot: ParameterSlot
    let selection: ComparisonOperator

    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            FormulaSlotEditor(editor: editor, target: .operand(slot, .first))
        } header: {
            Text(ParameterEditorText.title(of: ComparisonSide.first, locale: locale))
        }
        Section {
            ComparisonOperatorPicker(editor: editor, slot: slot, selection: selection)
        }
        Section {
            FormulaSlotEditor(editor: editor, target: .operand(slot, .second))
        } header: {
            Text(ParameterEditorText.title(of: ComparisonSide.second, locale: locale))
        }
    }
}

/// The operator, as a menu: six choices named in words, so VoiceOver speaks "Less than" and a
/// child who cannot read `≤` yet can still choose it. A segmented row of glyphs would neither
/// grow with Dynamic Type nor say anything (`swift-ui-design`, slice 7).
///
/// The setter is a closure literal, as in `ArcDirectionPicker` (Release-build crash, PR #72).
struct ComparisonOperatorPicker: View {
    let editor: EditorViewModel
    let slot: ParameterSlot
    let selection: ComparisonOperator

    @Environment(\.locale) private var locale

    var body: some View {
        Picker(selection: comparison) {
            ForEach(ComparisonOperator.allCases, id: \.self) { comparison in
                Label {
                    Text(ParameterEditorText.name(of: comparison, locale: locale))
                } icon: {
                    Image(systemName: Self.symbol(for: comparison))
                }
                .tag(comparison)
            }
        } label: {
            Text(ParameterEditorText.comparisonTitle(locale: locale))
        }
        .pickerStyle(.menu)
    }

    private var comparison: Binding<ComparisonOperator> {
        Binding {
            selection
        } set: { chosen in
            editor.setComparisonOperator(chosen, in: slot)
        }
    }

    static func symbol(for comparison: ComparisonOperator) -> String {
        switch comparison {
        case .equal: "equal"
        case .notEqual: "notequal"
        case .smallerThan: "lessthan"
        case .smallerOrEqual: "lessthanorequalto"
        case .greaterThan: "greaterthan"
        case .greaterOrEqual: "greaterthanorequalto"
        }
    }
}
