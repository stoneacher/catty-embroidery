import EditorCore
import ProgramModel
import Testing

/// Brick backend slice 1: function arguments are formula nodes like any other,
/// so they count toward `ProgramDocument.maximumFormulaDepth`. A codec walk that
/// treated a call as a leaf would admit an unbounded tree behind one `sqrt`.
/// (Beside `ProgramDocumentAdmissionTests`, whose depth tests these extend.)
@Suite("Program document admission: function depth")
struct ProgramDocumentFunctionDepthTests {
    static func functionChain(depth: Int, second: Bool = false) -> Formula {
        (1 ..< depth).reduce(Formula.number(0)) { tree, _ in
            second ? .binaryFunction(.max, .number(1), tree) : .unaryFunction(.sqrt, tree)
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

    @Test("the depth limit counts a binary function's second argument")
    func depthLimitCountsBinaryFunctions() {
        let past = Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: [
            .setVariable(name: "v", to: Self.functionChain(depth: 129, second: true))
        ])])])])
        #expect(throws: ProgramDocumentError.formulaTooDeep(limit: 128)) {
            _ = try ProgramDocument.encode(past)
        }
    }
}
