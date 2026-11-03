import ProgramModel

/// Reads one brick's formulas by Catroid `BrickField` category, and maps the
/// bricks with no nested lists (brief slice 4). Collects its own blockers; a
/// missing part is reported once, as the brick's shape.
struct BrickReader {
    let element: XMLTree.Element
    let type: String
    private(set) var blockers: [ImportBlocker] = []
    private var unknown = false
    /// The categories read so far; any other in the `formulaList` is refused.
    private var read: Set<String> = []

    init(element: XMLTree.Element, type: String) {
        self.element = element
        self.type = type
    }

    /// The `<formula category="…">` of the brick's `formulaList`.
    mutating func formulaElement(_ category: String) -> XMLTree.Element? {
        read.insert(category)
        return element.child("formulaList")?.children.first {
            $0.name == "formula" && $0.attributes["category"] == category
        }
    }

    /// Catroid fails to load a category that is no `BrickField`
    /// (`XStreamConcurrentFormulaHashMapConverter.java:75`); a category the brick
    /// never reads is refused with it (Codex slice 4, finding 4). An unsupported
    /// brick is already named, so nothing is added for it.
    mutating func refuseUnreadCategories() {
        guard !unknown else { return }
        let categories = element.child("formulaList")?.children.compactMap { $0.attributes["category"] } ?? []
        if categories.contains(where: { !read.contains($0) }) { refuse() }
    }

    mutating func formula(_ category: String, slot: FormulaSlot = .number) -> Formula? {
        guard let formula = formulaElement(category) else {
            refuse()
            return nil
        }
        return FormulaImport.formula(from: formula, slot: slot, blockers: &blockers)
    }

    /// A formula Catroid interprets as text (`interpretString`), which only a
    /// literal can carry into a `String` payload.
    mutating func text(_ category: String) -> String? {
        guard let formula = formulaElement(category) else {
            refuse()
            return nil
        }
        guard let text = FormulaImport.literalText(of: formula) else {
            blockers.append(.stringValue(.text))
            return nil
        }
        return text
    }

    /// The brick lacks a part it needs or has one it cannot map. Repeats collapse:
    /// the import reports a set.
    mutating func refuse() {
        blockers.append(.brickShape(type))
    }

    private static let common: Set = ["brickId", "commentedOut", "formulaList"]

    /// The child elements each brick may carry beyond `common`.
    private static let extraChildren: [String: Set<String>] = [
        "RepeatBrick": ["loopBricks"], "ForeverBrick": ["loopBricks"], "RepeatUntilBrick": ["loopBricks"],
        "ForVariableFromToBrick": ["loopBricks", "userVariable"],
        "IfLogicBeginBrick": ["ifBranchBricks", "elseBranchBricks"], "IfThenLogicBeginBrick": ["ifBranchBricks"],
        "SetVariableBrick": ["userVariable"], "ChangeVariableBrick": ["userVariable"],
        "ArcBrick": ["direction"]
    ]

    /// A child the brick has no use for is refused rather than dropped, so a
    /// nested list only some bricks read cannot lose its bricks silently.
    mutating func refuseUnknownChildren() {
        guard !unknown else { return }
        let allowed = Self.common.union(Self.extraChildren[type] ?? [])
        if element.children.contains(where: { !allowed.contains($0.name) }) { refuse() }
    }

    /// Bricks without nested lists. Each formula is read even when an earlier one
    /// failed, so every blocker is collected.
    mutating func leaf() -> Brick? {
        switch type {
        case "MoveNStepsBrick": return formula("STEPS").map(Brick.moveNSteps)
        case "TurnLeftBrick": return formula("TURN_LEFT_DEGREES").map(Brick.turnLeft)
        case "TurnRightBrick": return formula("TURN_RIGHT_DEGREES").map(Brick.turnRight)
        case "PointInDirectionBrick": return formula("DEGREES").map(Brick.pointInDirection)
        case "PlaceAtBrick":
            let x = formula("X_POSITION"), y = formula("Y_POSITION")
            return zip(x, y).map { Brick.placeAt(x: $0, y: $1) }
        case "SetXBrick": return formula("X_POSITION").map(Brick.setX)
        case "SetYBrick": return formula("Y_POSITION").map(Brick.setY)
        case "ChangeXByNBrick": return formula("X_POSITION_CHANGE").map(Brick.changeXBy)
        case "ChangeYByNBrick": return formula("Y_POSITION_CHANGE").map(Brick.changeYBy)
        case "ArcBrick":
            let radius = formula("SIZE"), degrees = formula("DEGREES")
            let direction: ArcDirection? = switch element.child("direction")?.text {
            case "LEFT": .left
            case "RIGHT": .right
            default: nil
            }
            if direction == nil {
                refuse()
            }
            guard let direction, let radius, let degrees else { return nil }
            return .arc(direction: direction, radius: radius, degrees: degrees)
        case "GoThroughBrick":
            // X/Y_POSITION are the through point (`GoThroughAction.kt`'s x1, y1).
            let throughX = formula("X_POSITION"), throughY = formula("Y_POSITION")
            let x = formula("X_DESTINATION"), y = formula("Y_DESTINATION")
            guard let throughX, let throughY, let x, let y else { return nil }
            return .goThrough(throughX: throughX, throughY: throughY, x: x, y: y)
        case "WaitBrick": return formula("TIME_TO_WAIT_IN_SECONDS").map { .wait(seconds: $0) }
        case "WaitUntilBrick": return formula("IF_CONDITION").map { .waitUntil(condition: $0) }
        case "StitchBrick": return .stitch
        case "SewUpBrick": return .sewUp
        case "StopRunningStitchBrick": return .stopRunningStitch
        case "RunningStitchBrick": return formula("EMBROIDERY_LENGTH").map { .runningStitch(length: $0) }
        case "TripleStitchBrick": return formula("EMBROIDERY_LENGTH").map { .tripleStitch(length: $0) }
        case "ZigZagStitchBrick":
            let length = formula("ZIGZAG_EMBROIDERY_LENGTH"), width = formula("ZIGZAG_EMBROIDERY_WIDTH")
            return zip(length, width).map { Brick.zigZagStitch(length: $0, width: $1) }
        case "SetThreadColorBrick": return text("THREAD_COLOR").map { .setThreadColor(hex: $0) }
        case "WriteEmbroideryToFileBrick": return text("WRITE_FILENAME").map { .writeEmbroideryToFile(name: $0) }
        default:
            unknown = true
            blockers.append(.brick(type))
            return nil
        }
    }

    private func zip<A, B>(_ first: A?, _ second: B?) -> (A, B)? {
        guard let first, let second else { return nil }
        return (first, second)
    }
}
