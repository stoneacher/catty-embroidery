import CatrobatImport
import Foundation
import ProgramModel
import Testing

/// Slice 3 over the real corpus: every `<formula>` in the 215 files either imports
/// or names why not, and never traps. The slot is read from the formula's
/// `category` here; slice 4 takes it from the brick instead.
struct CorpusFormulaTests {
    static func slot(forCategory category: String?) -> FormulaSlot? {
        switch category {
        case "NOTE": nil // a NoteBrick is dropped (brief D7)
        case "ASSERT_EQUALS_ACTUAL", "ASSERT_EQUALS_EXPECTED": .assertOperand
        case "VARIABLE": .variableValue
        default: .number
        }
    }

    /// Each formula's outcome: "ok", or the sorted set of its blocker kinds.
    static func outcomes() throws -> [String: Int] {
        var outcomes: [String: Int] = [:]
        for entry in try LanguageTestCatalog.manifest().tests {
            let tree = try XMLTree(parsing: LanguageTestCatalog.codeXML(for: entry.path))
            for address in tree.addresses(where: { $0.name == "formula" && $0.attributes["category"] != nil }) {
                let element = try #require(tree[address])
                guard let slot = slot(forCategory: element.attributes["category"]) else { continue }
                var blockers: [ImportBlocker] = []
                let formula = FormulaImport.formula(from: element, slot: slot, blockers: &blockers)
                #expect((formula == nil) == !blockers.isEmpty, "\(entry.path)")
                let kinds = Set(blockers.map(kind(of:)))
                outcomes[kinds.isEmpty ? "ok" : kinds.sorted().joined(separator: "+"), default: 0] += 1
            }
        }
        return outcomes
    }

    static func kind(of blocker: ImportBlocker) -> String {
        switch blocker {
        case .malformed: "malformed"
        case .unresolvedReference: "unresolvedReference"
        case let .elementType(type): "elementType(\(type))"
        case let .function(name): "function(\(name))"
        case let .sensor(name): "sensor(\(name))"
        case let .operatorName(name): "operator(\(name))"
        case let .stringValue(context): "stringValue(\(context))"
        case let .nonFiniteLiteral(text): "nonFinite(\(text))"
        case let .formulaShape(shape): "shape(\(shape))"
        case .formulaTooDeep: "tooDeep"
        case let .version(text): "version(\(text))"
        case .multipleScenes: "multipleScenes"
        case let .brick(name): "brick(\(name))"
        case let .script(name): "script(\(name))"
        case let .element(name): "element(\(name))"
        case let .brickShape(name): "brickShape(\(name))"
        case let .variableShadowing(name): "variableShadowing(\(name))"
        case let .variableStorage(name): "variableStorage(\(name))"
        case let .undeclaredVariable(name): "undeclaredVariable(\(name))"
        case .harnessStep: "harnessStep"
        }
    }

    /// The outcome of every formula in the corpus, pinned. It is the formula
    /// importer's regression oracle over real data: a change in how any construct
    /// imports moves a count. There are no shapes, non-finite literals or too-deep
    /// formulas in the corpus; every refusal names a construct out of scope
    /// (ADR-001) or a string Catroid would keep as a string (brief D4).
    @Test func outcomesAcrossTheCorpus() throws {
        #expect(try Self.outcomes() == [
            "elementType(COLLISION_FORMULA)": 28,
            "elementType(USER_DEFINED_BRICK_INPUT)": 14,
            "elementType(USER_LIST)": 20,
            "elementType(USER_LIST)+function(NUMBER_OF_ITEMS)": 1,
            "elementType(USER_LIST)+stringValue(equality)": 5,
            "function(COLLIDES_WITH_COLOR)": 26,
            "function(COLOR_AT_XY)": 28,
            "function(COLOR_EQUALS_COLOR)": 50,
            "function(COLOR_TOUCHES_COLOR)": 13,
            "function(CONTAINS)": 8,
            "function(FLATTEN)": 13,
            "function(IF_THEN_ELSE)": 11,
            "function(INDEX_CURRENT_TOUCH)": 3,
            "function(INDEX_OF_ITEM)": 13,
            "function(JOIN)": 23,
            "function(JOIN3)": 5,
            "function(LENGTH)": 11,
            "function(LENGTH)+function(LIST_ITEM)+function(REGEX)+stringValue(equality)": 1,
            "function(LETTER)": 11,
            "function(LIST_ITEM)": 22,
            "function(NUMBER_OF_ITEMS)": 57,
            "function(RAND)": 15,
            "function(REGEX)": 68,
            "ok": 2654,
            "sensor(DATE_YEAR)": 1,
            "sensor(FINGER_TOUCHED)": 2,
            "sensor(LOOK_DIRECTION)": 10,
            "sensor(NUMBER_CURRENT_TOUCHES)": 5,
            "sensor(OBJECT_BACKGROUND_NAME)": 1,
            "sensor(OBJECT_BACKGROUND_NUMBER)": 5,
            "sensor(OBJECT_BRIGHTNESS)": 12,
            "sensor(OBJECT_LOOK_NAME)": 2,
            "sensor(OBJECT_LOOK_NUMBER)": 2,
            "sensor(OBJECT_NUMBER_OF_LOOKS)": 15,
            "sensor(OBJECT_ROTATION)": 2,
            "sensor(OBJECT_SIZE)": 11,
            "sensor(OBJECT_TRANSPARENCY)": 6,
            "sensor(OBJECT_X_VELOCITY)": 4,
            "sensor(OBJECT_Y_VELOCITY)": 10,
            "sensor(STAGE_HEIGHT)": 3,
            "sensor(STAGE_WIDTH)": 3,
            "sensor(TIMER)": 11,
            "stringValue(assertOperand)": 130,
            "stringValue(equality)": 17,
            "stringValue(variableValue)": 58
        ])
    }
}
