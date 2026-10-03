import EditorCore
import Foundation

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
    static func title(of slot: ParameterSlot, locale: Locale = .current) -> String {
        let resource: LocalizedStringResource = switch slot {
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
        }
        return resolve(resource, locale: locale)
    }

    private static func resolve(_ resource: LocalizedStringResource, locale: Locale) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }
}
