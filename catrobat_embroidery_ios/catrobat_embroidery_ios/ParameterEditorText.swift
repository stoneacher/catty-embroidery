import EditorCore
import Foundation
import ProgramModel

/// The parameter editor's localized copy (US-410): one mapping per package reason, since
/// `EditorCore` ships no resources (ADR-025's `Field` pattern, ADR-039).
///
/// **Values, not views**, so tests can read every message. Each mapping is exhaustive with no
/// `default:`, so a new reason in the package is a compile error here rather than an empty line
/// under a field.
nonisolated enum ParameterEditorText {
    static func message(for error: FormulaLiteralError, locale: Locale = .current) -> String {
        let resource: LocalizedStringResource = switch error {
        case .empty: .parameterLiteralErrorEmpty
        case .malformed: .parameterLiteralErrorMalformed
        case .nonFinite: .parameterLiteralErrorTooLarge
        }
        return resolve(resource, locale: locale)
    }

    static func message(for problem: VariableNameProblem, locale: Locale = .current) -> String {
        let resource: LocalizedStringResource = switch problem {
        case .empty: .parameterNameErrorEmpty
        case .surroundingWhitespace: .parameterNameErrorWhitespace
        case .controlCharacter: .parameterNameErrorControl
        case .quotationMark: .parameterNameErrorQuote
        case .leadingOpenPunctuation: .parameterNameErrorBracket
        }
        return resolve(resource, locale: locale)
    }

    /// A visible sentence, not a disabled control with no explanation — which reads as a bug.
    static func message(for reason: ReadOnlyFormulaReason, locale: Locale = .current) -> String {
        let resource: LocalizedStringResource = switch reason {
        case .binary: .parameterReadonlyBinary
        case .unaryMinus: .parameterReadonlyNegation
        case .function: .parameterReadonlyFunction
        case .sensor: .parameterReadonlySensor
        case .logic: .parameterReadonlyLogic
        }
        return resolve(resource, locale: locale)
    }

    /// The swatch's spoken and shown name — selection must not be conveyed by colour alone.
    static func name(of swatch: ThreadSwatch, locale: Locale = .current) -> String {
        let resource: LocalizedStringResource = switch swatch {
        case .black: .threadColorBlack
        case .white: .threadColorWhite
        case .red: .threadColorRed
        case .orange: .threadColorOrange
        case .amber: .threadColorAmber
        case .yellow: .threadColorYellow
        case .green: .threadColorGreen
        case .teal: .threadColorTeal
        case .royalBlue: .threadColorRoyalBlue
        case .navy: .threadColorNavy
        case .purple: .threadColorPurple
        case .pink: .threadColorPink
        case .brown: .threadColorBrown
        case .grey: .threadColorGrey
        }
        return resolve(resource, locale: locale)
    }

    /// The label of a slot's control.
    /// `kind` is the brick being edited, where a slot's name depends on it: GoThrough's
    /// destination is "To x"/"To y" (Catroid's "then to"), so it does not read as a bare "X"
    /// beside "Through x". Required, not defaulted: a caller that left it out would
    /// label GoThrough's destination "X" again (`swift-code-reviewer`, PR 2).
    static func title(of slot: ParameterSlot, in kind: BrickKind?, locale: Locale = .current) -> String {
        let resource: LocalizedStringResource = switch (kind, slot) {
        case (.goThrough, .x): .parameterSlotToX
        case (.goThrough, .y): .parameterSlotToY
        default: baseTitle(of: slot)
        }
        return resolve(resource, locale: locale)
    }

    /// A slot's name wherever the brick does not change it.
    private static func baseTitle(of slot: ParameterSlot) -> LocalizedStringResource {
        switch slot {
        case .steps: .parameterSlotSteps
        case .degrees: .parameterSlotDegrees
        case .x: .parameterSlotX
        case .y: .parameterSlotY
        case .times: .parameterSlotTimes
        case .seconds: .parameterSlotSeconds
        case .value: .parameterSlotValue
        case .length: .parameterSlotLength
        case .width: .parameterSlotWidth
        case .variableName: .parameterSlotVariable
        case .hex: .parameterSlotThread
        case .fileName: .parameterSlotFile
        case .direction: .parameterSlotDirection
        case .radius: .parameterSlotRadius
        case .throughX: .parameterSlotThroughX
        case .throughY: .parameterSlotThroughY
        case .condition: .parameterSlotCondition
        }
    }

    /// An Arc side's name in the direction picker.
    static func name(of direction: ArcDirection, locale: Locale = .current) -> String {
        let resource: LocalizedStringResource = switch direction {
        case .left: .parameterArcLeft
        case .right: .parameterArcRight
        }
        return resolve(resource, locale: locale)
    }

    private static func resolve(_ resource: LocalizedStringResource, locale: Locale) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }
}
