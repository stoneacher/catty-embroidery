import ProgramModel

/// Why a program could not become a document, or a document a program
/// (US-404, ADR-037).
///
/// `unbalancedScript` and `formulaTooDeep` are the point: a file we can parse
/// but must not open is not a file we cannot parse. Collapsing either into
/// `corrupt` would lose exactly that distinction.
public enum ProgramDocumentError: Error, Equatable, Sendable {
    /// The document carries a format version this build does not read. No
    /// migration exists (that is M5's); the file is left alone.
    case unsupportedVersion(Int)
    /// The bytes are not a readable version-1 program: not JSON, truncated, a
    /// missing or mistyped key, an unknown brick case, a non-finite number.
    case corrupt
    /// The program could not be encoded: a non-finite `Double` reached through
    /// the model API (ADR-017 leaves the model permissive). Depth is refused
    /// before encoding, as `formulaTooDeep`.
    case encodingFailed
    /// A structurally valid program whose control bricks do not balance. The
    /// reason is `Script.validate()`'s, propagated rather than restated.
    case unbalancedScript(ScriptValidationError)
    /// A formula nests deeper than `ProgramDocument.maximumFormulaDepth`, which
    /// the payload names so the message can state it. Added at review
    /// (Sebastian, 2026-09-25, ADR-037) — a fifth case beside the story's four.
    case formulaTooDeep(limit: Int)
}
