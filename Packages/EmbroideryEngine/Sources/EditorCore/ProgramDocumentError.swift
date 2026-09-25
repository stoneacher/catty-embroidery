import ProgramModel

/// Why a program could not become a document, or a document a program
/// (US-404, ADR-037).
///
/// Four cases, and the fourth is the point: a file we can parse but must not
/// open is not a file we cannot parse. Collapsing `unbalancedScript` into
/// `corrupt` would lose exactly that distinction.
public enum ProgramDocumentError: Error, Equatable, Sendable {
    /// The document carries a format version this build does not read. No
    /// migration exists (that is M5's); the file is left alone.
    case unsupportedVersion(Int)
    /// The bytes are not a readable version-1 program: not JSON, truncated, a
    /// missing or mistyped key, an unknown brick case, a non-finite number.
    case corrupt
    /// The program could not be encoded — a non-finite `Double` reached through
    /// the model API, or a formula nested past the encoder's depth limit.
    case encodingFailed
    /// A structurally valid program whose control bricks do not balance. The
    /// reason is `Script.validate()`'s, propagated rather than restated.
    case unbalancedScript(ScriptValidationError)
}
