import Foundation
import ProgramModel

/// The program as a file, and back (US-404, ADR-037). **Pure** — no
/// `FileManager`, no `URL`; touching the disk is US-406's, the same split
/// US-308 drew between `DSTDesign` and `DSTFileWriting`.
///
/// Typed throws because this is a boundary (ADR-033: boundary conversions throw,
/// the inner `apply` funnel returns a value), so a caller switches over four
/// cases rather than casting.
///
/// The contract is symmetric: **whatever `encode` returns, `decode` accepts.**
/// Both refuse a foreign version and an unbalanced script, so an autosave can
/// never write a file the next launch would refuse and set aside.
public enum ProgramDocument {
    /// The document's bytes for `program`.
    ///
    /// Keeps the default non-conforming-float strategy (`.throw`): one format,
    /// one encoding, the same one `SampleJSONResourceTests` guards. The output
    /// formatting matches the sample regeneration — presentation only, so the
    /// bytes are deterministic and an autosave diffs legibly.
    public static func encode(_ program: Program) throws(ProgramDocumentError) -> Data {
        try admit(program)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(program)
        } catch {
            throw .encodingFailed
        }
    }

    /// The program in `data`, or why it cannot be opened.
    ///
    /// The version is read **first**, from a probe that ignores every other key:
    /// a later format is free to change shape, and a full decode would report
    /// such a file as corrupt instead of as a version this build does not read.
    public static func decode(_ data: Data) throws(ProgramDocumentError) -> Program {
        let decoder = JSONDecoder()
        let version: Int
        do {
            version = try decoder.decode(VersionProbe.self, from: data).formatVersion
        } catch {
            throw .corrupt
        }
        try admit(version: version)

        let program: Program
        do {
            program = try decoder.decode(Program.self, from: data)
        } catch {
            throw .corrupt
        }
        try admit(program)
        return program
    }

    // MARK: Admission

    private struct VersionProbe: Decodable {
        let formatVersion: Int
    }

    /// `!=` rather than `>`: no version below 1 was ever written, so there is
    /// nothing to migrate from and nothing to open.
    private static func admit(version: Int) throws(ProgramDocumentError) {
        guard version == Program.currentFormatVersion else {
            throw .unsupportedVersion(version)
        }
    }

    /// The version, then every script in scene → object → script order; the
    /// first imbalance found is the reason.
    private static func admit(_ program: Program) throws(ProgramDocumentError) {
        try admit(version: program.formatVersion)
        for scene in program.scenes {
            for object in scene.objects {
                for script in object.scripts {
                    do {
                        try script.validate()
                    } catch let error as ScriptValidationError {
                        throw .unbalancedScript(error)
                    } catch {
                        // Unreachable: `validate()` throws only
                        // `ScriptValidationError`, but its signature is untyped.
                        // No mutation can reach this branch.
                        throw .corrupt
                    }
                }
            }
        }
    }
}
