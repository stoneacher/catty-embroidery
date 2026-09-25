import Foundation
import ProgramModel

/// The program as a file, and back (US-404, ADR-037). **Pure** — no
/// `FileManager`, no `URL`; touching the disk is US-406's, the same split
/// US-308 drew between `DSTDesign` and `DSTFileWriting`.
///
/// Typed throws because this is a boundary (ADR-033: boundary conversions throw,
/// the inner `apply` funnel returns a value), so a caller switches over the
/// error's cases rather than casting.
///
/// The contract is symmetric: **whatever `encode` returns, `decode` accepts.**
/// Both refuse a foreign version, an unbalanced script and a formula deeper than
/// `maximumFormulaDepth`, so an autosave can never write a file the next launch
/// would refuse and set aside, and nothing decode admits fails to re-encode.
public enum ProgramDocument {
    /// The deepest formula the document admits, counted in `Formula` nodes on
    /// the longest root-to-leaf path (a bare literal is 1).
    ///
    /// Without a cap, the failure mode of a deep formula depended on the
    /// thread's stack: `JSONEncoder` spends two JSON levels per node and threw
    /// at ~250 deep on the 8 MB main thread, but overflowed the stack — a crash,
    /// not a throw — from ~230 on a cooperative-pool thread (measured by
    /// `swift-code-reviewer`, debug build). 128 is half the main-thread ceiling,
    /// deep enough for any formula a person writes, and M6's formula editor
    /// inherits it as a named limit rather than a stack-size accident (ADR-037).
    public static let maximumFormulaDepth = 128

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

    /// The version, then every script in scene → object → script order; for
    /// each script its balance, then its formulas' depth. The first failure
    /// found is the reason.
    private static func admit(_ program: Program) throws(ProgramDocumentError) {
        try admit(version: program.formatVersion)
        for scene in program.scenes {
            for object in scene.objects {
                for script in object.scripts {
                    do {
                        try script.validate()
                    } catch {
                        throw .unbalancedScript(error)
                    }
                    for brick in script.bricks {
                        for formula in brick.formulas where formula.exceedsDepth(maximumFormulaDepth) {
                            throw .formulaTooDeep(limit: maximumFormulaDepth)
                        }
                    }
                }
            }
        }
    }
}

private extension Brick {
    /// Every formula this brick carries. Exhaustive on purpose: a new brick case
    /// with a formula payload must be added here, or the compiler says so.
    var formulas: [Formula] {
        switch self {
        case let .moveNSteps(formula), let .turnLeft(formula), let .turnRight(formula),
             let .pointInDirection(formula), let .setX(formula), let .setY(formula),
             let .changeXBy(formula), let .changeYBy(formula),
             let .repeatLoop(times: formula), let .wait(seconds: formula),
             let .setVariable(_, to: formula), let .changeVariableBy(_, value: formula),
             let .runningStitch(length: formula), let .tripleStitch(length: formula):
            [formula]
        case let .placeAt(x, y):
            [x, y]
        case let .zigZagStitch(length, width):
            [length, width]
        case .forever, .loopEnd, .stitch, .setThreadColor, .sewUp, .stopRunningStitch,
             .writeEmbroideryToFile:
            []
        }
    }
}

private extension Formula {
    /// Whether some root-to-leaf path holds more than `limit` `Formula` nodes (a
    /// bare literal is 1).
    ///
    /// **Iterative and bounded** (Codex round 1): an explicit stack, and no node
    /// deeper than `limit + 1` is ever visited, so the cost is independent of how
    /// deep the tree really is. A recursive walk of the whole tree overflowed the
    /// stack on a model-built chain 100 000 deep instead of refusing it.
    func exceedsDepth(_ limit: Int) -> Bool {
        var pending: [(formula: Formula, depth: Int)] = [(self, 1)]
        while let (formula, depth) = pending.popLast() {
            guard depth <= limit else {
                return true
            }
            switch formula {
            case .number, .variable:
                break
            case let .unaryMinus(operand):
                pending.append((operand, depth + 1))
            case let .binary(_, left, right):
                pending.append((left, depth + 1))
                pending.append((right, depth + 1))
            }
        }
        return false
    }
}
