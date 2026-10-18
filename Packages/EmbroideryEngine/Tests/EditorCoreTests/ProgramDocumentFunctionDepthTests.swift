import EditorCore
import ProgramModel
import Testing

/// Brick backend slice 1: function arguments are formula nodes like any other,
/// so they count toward `ProgramDocument.maximumFormulaDepth`. A codec walk that
/// treated a call as a leaf would admit an unbounded tree behind one `sqrt`.
/// (Beside `ProgramDocumentAdmissionTests`, whose depth tests these extend.)
@Suite("Program document admission: function depth")
struct ProgramDocumentFunctionDepthTests {
    enum Nesting { case unary, firstArgument, secondArgument }

    static func functionChain(depth: Int, nesting: Nesting = .unary) -> Formula {
        (1 ..< depth).reduce(Formula.number(0)) { tree, _ in
            switch nesting {
            case .unary: .unaryFunction(.sqrt, tree)
            case .firstArgument: .binaryFunction(.max, tree, .number(1))
            case .secondArgument: .binaryFunction(.max, .number(1), tree)
            }
        }
    }

    @Test("the depth limit counts unary function arguments")
    func depthLimitCountsUnaryFunctions() throws {
        let atLimit = Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: [
            .setVariable(name: "v", to: Self.functionChain(depth: 128))
        ])])])])
        #expect(try ProgramDocument.decode(ProgramDocument.encode(atLimit)) == atLimit)
        let past = Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: [
            .setVariable(name: "v", to: Self.functionChain(depth: 129))
        ])])])])
        #expect(throws: ProgramDocumentError.formulaTooDeep(limit: 128)) {
            _ = try ProgramDocument.encode(past)
        }
    }

    /// Both arguments, each on its own: a walk skipping either one passes a test
    /// that only nests in the other (both reviews of slice 1).
    @Test("the depth limit counts each binary function argument", arguments: [
        Nesting.firstArgument, .secondArgument
    ])
    func depthLimitCountsBinaryFunctions(_ nesting: Nesting) {
        let past = Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: [
            .setVariable(name: "v", to: Self.functionChain(depth: 129, nesting: nesting))
        ])])])])
        #expect(throws: ProgramDocumentError.formulaTooDeep(limit: 128)) {
            _ = try ProgramDocument.encode(past)
        }
    }
}
