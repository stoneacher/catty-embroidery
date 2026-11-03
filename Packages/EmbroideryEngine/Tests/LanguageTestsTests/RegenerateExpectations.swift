import CatrobatImport
import Foundation
import Interpreter
import Testing

/// Regenerates `LanguageTestExpectations.swift` from the importer and runner, so the
/// table is never rebuilt by hand. Off unless `REGENERATE_LANGUAGE_TESTS` is set;
/// `scripts/regenerate-language-test-expectations.sh` runs it and writes the file.
/// An expected failure keeps the owner the table already names; a new one gets a
/// placeholder owner, to be replaced before it is committed.
struct RegenerateExpectations {
    static let begin = "BEGIN LanguageTestExpectations.swift"
    static let end = "END LanguageTestExpectations.swift"

    @Test(.enabled(if: ProcessInfo.processInfo.environment["REGENERATE_LANGUAGE_TESTS"] != nil))
    func printTheExpectationTable() throws {
        var lines: [String] = []
        for entry in try LanguageTestCatalog.manifest().tests {
            switch try CorpusProgramTests.outcome(of: entry) {
            case let .failure(error):
                let labels = error.blockers.map(\.label).sorted().map(Self.literal).joined(separator: ", ")
                lines.append("        \(Self.literal(entry.path)): .unsupported([\(labels)]),")
            case let .success(program):
                let run = LanguageTestRunner.run(program)
                switch run.outcome {
                case .passed:
                    lines.append("        \(Self.literal(entry.path)): .pass,")
                case let .assertionFailed(failure):
                    let owner = if case let .expectedFailure(_, owner) = LanguageTestExpectation.all[entry.path] {
                        owner
                    } else {
                        "TODO: name the ADR or backlog item that owns this failure"
                    }
                    lines.append("""
                            \(Self.literal(entry.path)): .expectedFailure(
                                HarnessAssertionFailure(
                                    objectIndex: \(failure.objectIndex), scriptIndex: \(failure.scriptIndex), \
                    stepIndex: \(failure.stepIndex),
                                    expected: \(failure.expected), actual: \(failure.actual)
                                ),
                                owner: \(Self.literal(owner))
                            ),
                    """)
                case .endedWithoutResult, .budgetExhausted:
                    Issue.record("\(entry.path) imports but neither passes nor fails an assert: \(run.outcome)")
                }
            }
        }
        if let last = lines.indices.last {
            lines[last].removeLast() // no trailing comma (SwiftLint)
        }
        print(Self.begin)
        print(Self.header + lines.joined(separator: "\n") + "\n    ]\n}\n\n// swiftlint:enable line_length")
        print(Self.end)
    }

    static func literal(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case _ where scalar.value < 0x20 || scalar.value > 0x7E: out += "\\u{\(String(scalar.value, radix: 16))}"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    static let header = """
    // Generated data, one test per line: line length follows the blockers' names.
    // swiftlint:disable line_length
    import Interpreter

    /// The pinned class of every one of the 215 Catrobat language tests (brief D12).
    /// A test that changes class turns `LanguageTestRunnerTests` red until this table
    /// is updated on purpose. Generated: run
    /// `scripts/regenerate-language-test-expectations.sh`, then review the diff and
    /// name the owner of any new expected failure. Never edited by hand otherwise.
    enum LanguageTestExpectation: Sendable, Equatable {
        /// Imports, runs, and reaches FinishStage within the budget.
        case pass
        /// Imports and runs to exactly this assertion failure, for a reason an ADR or
        /// backlog item owns.
        case expectedFailure(HarnessAssertionFailure, owner: String)
        /// Refused by the importer with exactly these blockers (`ImportBlocker.label`).
        case unsupported(Set<String>)
    }

    extension LanguageTestExpectation {
        static let all: [String: LanguageTestExpectation] = [

    """
}
