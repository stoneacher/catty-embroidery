import EditorCore
import Foundation
import ProgramModel
import Testing

/// One tag per `Formula` case. `init(of:)` is an exhaustive switch, so a new
/// `Formula` case does not compile here until it gets a tag — and then
/// `censusCoversEveryCase` fails until `FormulaCensus.examples` holds one.
/// That is the guard for `Formula.==`'s `default: false` (Brick backend,
/// slice 0): a case whose same-case arm is forgotten falls into the default,
/// and the reflexivity property below goes red.
enum FormulaCase: CaseIterable {
    case number, variable, binary, unaryMinus

    init(of formula: Formula) {
        switch formula {
        case .number: self = .number
        case .variable: self = .variable
        case .binary: self = .binary
        case .unaryMinus: self = .unaryMinus
        }
    }
}

enum FormulaCensus {
    /// Finite examples of every case: these must survive the document codec.
    static let finite: [Formula] = ProgramDocumentRoundTripTests.everyFormula + [
        .unaryMinus(.unaryMinus(.number(1))),
        .binary(.divide, .unaryMinus(.variable("x")), .binary(.pow, .number(2), .number(0.5)))
    ]

    /// Non-finite payloads nested inside every composite case. They must be
    /// reflexive (ADR-006) but never reach disk (ADR-037).
    static let nonFinite: [Formula] = [
        .number(.nan),
        .number(.infinity),
        .unaryMinus(.number(.nan)),
        .binary(.plus, .variable("x"), .number(.nan)),
        .binary(.mult, .number(-.infinity), .unaryMinus(.number(.nan)))
    ]

    static let examples: [Formula] = finite + nonFinite
}

@Suite("Formula census")
struct FormulaCensusTests {
    @Test("The census holds an example of every Formula case")
    func censusCoversEveryCase() {
        let covered = Set(FormulaCensus.examples.map(FormulaCase.init(of:)))
        #expect(covered == Set(FormulaCase.allCases))
    }

    @Test("Every census formula equals itself, NaN payloads included", arguments: FormulaCensus.examples)
    func isReflexive(_ formula: Formula) {
        #expect(formula == formula)
    }

    @Test("Formulas of different cases never compare equal")
    func differentCasesAreUnequal() {
        for lhs in FormulaCensus.examples {
            for rhs in FormulaCensus.examples where FormulaCase(of: lhs) != FormulaCase(of: rhs) {
                #expect(lhs != rhs)
            }
        }
    }

    @Test("Every finite census formula round-trips through the document", arguments: FormulaCensus.finite)
    func roundTrips(_ formula: Formula) throws {
        let program = ProgramDocumentRoundTripTests.program(bricks: [.setVariable(name: "v", to: formula)])
        let decoded = try ProgramDocument.decode(ProgramDocument.encode(program))
        #expect(decoded == program)
    }

    @Test("A non-finite census formula is refused at encode", arguments: FormulaCensus.nonFinite)
    func nonFiniteIsRefused(_ formula: Formula) {
        let program = ProgramDocumentRoundTripTests.program(bricks: [.setVariable(name: "v", to: formula)])
        #expect(throws: ProgramDocumentError.encodingFailed) { try ProgramDocument.encode(program) }
    }
}
