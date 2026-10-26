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
        "not json at all", #"{"formatVersion": 1, "name": 42, "scenes": []}"#
    ])
    func corruptWithoutName(_ text: String) {
        #expect(ProgramDocument.inspect(Self.json(text)) == .refused(.corrupt, name: nil))
    }

    /// The name is the file's, verbatim and unvalidated: an empty or padded name is what the
    /// author's file says, and the list owns one fallback for an empty name, refused or not.
    @Test("the probed name is kept verbatim, even without a version", arguments: zip(
        [#"{"name": "No version"}"#, #"{"formatVersion": 1, "name": ""}"#, #"{"formatVersion": 1, "name": " X "}"#],
        ["No version", "", " X "]
    ))
    func verbatimName(_ text: String, _ name: String) {
        #expect(ProgramDocument.inspect(Self.json(text)) == .refused(.corrupt, name: name))
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

    /// The contract, over a fixture of each refusal kind and the samples: `.openable(p)` iff
    /// `decode` returns `p`, and a refusal carries `decode`'s own reason.
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

    /// Both directions, as an undo and its redo travel, and a change of letter case alone: the
    /// rule compares names exactly, not the way generated names are uniqued.
    @Test("only a change of name alone is rename-only", arguments: ["Moon", "star", "Star "])
    func renameOnly(_ name: String) {
        var renamed = Self.base
        renamed.name = name
        #expect(renamed.differsOnlyInName(from: Self.base))
        #expect(Self.base.differsOnlyInName(from: renamed))
        #expect(!Self.base.differsOnlyInName(from: Self.base))
    }

    /// `Program.==` treats the zeros as equal (ADR-017's `isSameValue`), but `arctan2(+0, -1)`
    /// is 180 and `arctan2(-0, -1)` is -180 (Codex slice 2 review): a rename carrying a sign
    /// change must still void the run, so the rule compares what would be persisted.
    @Test("a signed-zero change alongside a rename is not rename-only")
    func signedZero() {
        func program(_ zero: Double, named name: String) -> Program {
            Program(name: name, scenes: [Scene(objects: [Object(scripts: [Script(bricks: [
                .pointInDirection(.binaryFunction(.arctan2, .number(zero), .number(-1)))
            ])])])])
        }
        #expect(program(-0.0, named: "B") == program(0.0, named: "B"))
        #expect(!program(-0.0, named: "B").differsOnlyInName(from: program(0.0, named: "A")))
        #expect(program(-0.0, named: "B").differsOnlyInName(from: program(-0.0, named: "A")))
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
