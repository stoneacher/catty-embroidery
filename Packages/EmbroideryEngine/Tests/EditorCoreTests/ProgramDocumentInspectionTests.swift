import EditorCore
import Foundation
import ProgramModel
import Samples
import Testing

/// Project management slice 2 (brief D11): the project list shows every project file, including
/// ones it cannot open, so it needs a total, non-throwing reading of a file. `inspect` is
/// `decode` plus the name when a probe can read it: openable exactly when `decode` succeeds,
/// refused for the same reason otherwise.
@Suite("Program document inspection")
struct ProgramDocumentInspectionTests {
    private static func json(_ text: String) -> Data {
        Data(text.utf8)
    }

    private static func decoded(_ data: Data) -> Result<Program, ProgramDocumentError> {
        do {
            return try .success(ProgramDocument.decode(data))
        } catch {
            return .failure(error)
        }
    }

    @Test("every sample's checked-in file is openable and equal to its builder", arguments: SampleLibrary.all)
    func samples(_ sample: SampleProgram) throws {
        let url = try #require(sample.programJSONURL)
        #expect(try ProgramDocument.inspect(Data(contentsOf: url)) == .openable(sample.program))
    }

    @Test("a newer format is refused with its version and its name")
    func newerVersion() {
        let data = Self.json(#"{"formatVersion": 2, "name": "Future", "somethingNew": []}"#)
        #expect(ProgramDocument.inspect(data) == .refused(.unsupportedVersion(2), name: "Future"))
    }

    @Test("a malformed program keeps its readable name")
    func corruptWithName() {
        let data = Self.json(#"{"formatVersion": 1, "name": "Broken", "scenes": [{"objects": 7}], "variables": []}"#)
        #expect(ProgramDocument.inspect(data) == .refused(.corrupt, name: "Broken"))
    }

    @Test("bytes that are not a document, or a name that is not a string, give no name", arguments: [
        "not json at all", #"{"formatVersion": 1, "name": 42, "scenes": []}"#, #"{"name": "No version"}"#
    ])
    func corruptWithoutName(_ text: String) {
        let expected: DocumentInspection = text.contains("No version")
            ? .refused(.corrupt, name: "No version")
            : .refused(.corrupt, name: nil)
        #expect(ProgramDocument.inspect(Self.json(text)) == expected)
    }

    /// An unbalanced script and a formula past `maximumFormulaDepth`: both parse, both are
    /// refused by admission, and neither loses the name.
    @Test("a parseable program that admission refuses keeps its name and its reason", arguments: [
        Script(bricks: [.repeatLoop(times: .number(2)), .stitch]),
        Script(bricks: [.placeAt(x: .number(1), y: ProgramDocumentAdmissionTests.chain(depth: 129))])
    ])
    func admissionRefusal(_ script: Script) throws {
        let refused = Program(name: "Loose", scenes: [Scene(objects: [Object(scripts: [script])])])
        let data = try JSONEncoder().encode(refused)
        guard case let .failure(reason) = Self.decoded(data) else {
            Issue.record("decode admitted \(script)")
            return
        }
        #expect(reason != .corrupt)
        #expect(ProgramDocument.inspect(data) == .refused(reason, name: "Loose"))
    }

    /// The contract, over every fixture above and the samples: `.openable(p)` iff `decode`
    /// returns `p`, and a refusal carries `decode`'s own reason.
    @Test("inspect agrees with decode on every fixture")
    func agreesWithDecode() throws {
        var fixtures = [
            "not json", #"{"formatVersion": 2, "name": "F"}"#,
            #"{"formatVersion": 1, "name": "B", "scenes": [{"objects": 7}], "variables": []}"#
        ].map(Self.json)
        fixtures += try SampleLibrary.all.map { try ProgramDocument.encode($0.program) }
        for data in fixtures {
            switch (ProgramDocument.inspect(data), Self.decoded(data)) {
            case let (.openable(inspected), .success(decoded)):
                #expect(inspected == decoded)
            case let (.refused(inspected, _), .failure(decoded)):
                #expect(inspected == decoded)
            case let (inspection, decoding):
                Issue.record("inspect \(inspection) disagrees with decode \(decoding)")
            }
        }
    }

    // MARK: - Rename-only changes (brief D8)

    private static let base = Program(
        name: "Star",
        scenes: [Scene(objects: [Object(scripts: [Script(bricks: [.stitch])])])],
        variables: [Variable(name: "n")]
    )

    @Test("only a change of name alone is rename-only")
    func renameOnly() {
        var renamed = Self.base
        renamed.name = "Moon"
        #expect(renamed.differsOnlyInName(from: Self.base))
        #expect(!Self.base.differsOnlyInName(from: Self.base))
    }

    /// Every other persisted field, changed alone and together with the name, is not a
    /// rename-only change.
    @Test("any other field changed is not rename-only", arguments: [
        { (program: inout Program) in program.formatVersion = 2 },
        { (program: inout Program) in program.scenes = [] },
        { (program: inout Program) in program.variables = [] },
        { (program: inout Program) in program.scenes[0].objects[0].scripts[0].bricks.append(.stitch) }
    ] as [@Sendable (inout Program) -> Void])
    func otherFields(_ change: @Sendable (inout Program) -> Void) {
        var changed = Self.base
        change(&changed)
        #expect(!changed.differsOnlyInName(from: Self.base))
        changed.name = "Moon"
        #expect(!changed.differsOnlyInName(from: Self.base))
    }
}
