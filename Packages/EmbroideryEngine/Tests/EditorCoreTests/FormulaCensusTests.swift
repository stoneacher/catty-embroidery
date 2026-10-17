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

    /// Pairs that differ only in one payload, at least one per case. Reflexivity
    /// compares a value with itself, so it cannot see an arm that ignores its
    /// payload (`case (.variable, .variable): true`); these can (Codex slice
    /// review of slice 0).
    static let payloadSiblings: [(Formula, Formula)] = [
        (.number(1), .number(2)),
        (.variable("x"), .variable("y")),
        (.binary(.plus, .number(1), .number(2)), .binary(.minus, .number(1), .number(2))),
        (.binary(.plus, .number(1), .number(2)), .binary(.plus, .number(3), .number(2))),
        (.binary(.plus, .number(1), .number(2)), .binary(.plus, .number(1), .number(3))),
        (.unaryMinus(.number(1)), .unaryMinus(.number(2)))
    ]
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

    @Test("Formulas differing in one payload never compare equal, for every case")
    func payloadsAreCompared() {
        let covered = Set(FormulaCensus.payloadSiblings.map { FormulaCase(of: $0.0) })
        #expect(covered == Set(FormulaCase.allCases))
        for (lhs, rhs) in FormulaCensus.payloadSiblings {
            #expect(lhs != rhs, "\(lhs) vs \(rhs)")
        }
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
