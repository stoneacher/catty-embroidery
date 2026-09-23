import EditorCore
import ProgramModel
import Testing

/// US-402 test-plan item 9, and the acceptance criterion behind it: `apply` is
/// **total**. No index, no address and no malformed action traps it; every path
/// returns an `EditResult` (ADR-033).
///
/// A trapping implementation does not fail these tests, it **crashes the whole
/// `EditorCoreTests` bundle** and takes the other suites' results with it —
/// US-302's red phase recorded that, and US-401 hit it again with a raw
/// subscript in the addressing traversal. So the point of this suite is that the
/// crash arrives here, loudly, rather than in the app.
@Suite("EditorCore.apply — totality")
struct EditTotalityTests {
    typealias Fixtures = EditorCoreFixtures

    /// The fixture's real script holds ten bricks, so `10` is the first invalid
    /// *position*. `Int.min` earns its line: it is the value that traps any
    /// `abs(index)` or `-index` a later refactor might introduce, and `Int.max`
    /// traps any `index + 1`.
    static let invalidPositions = [-1, 10, 11, Int.min, Int.max]

    /// `delete`, `move` and `replaceBrick` address a **position** (`0 ..< count`).
    @Test("an out-of-bounds brick position is rejected in every positional case",
          arguments: invalidPositions)
    func outOfBoundsPosition(index: Int) {
        let address = Fixtures.at(index)
        let expected = EditResult.rejected(.addressOutOfBounds(.brick, at: address))
        #expect(EditorCore.apply(.delete(at: address), to: Fixtures.program) == expected)
        #expect(EditorCore.apply(.move(from: address, to: 0), to: Fixtures.program) == expected)
        #expect(
            EditorCore.apply(.replaceBrick(at: address, with: .stitch), to: Fixtures.program)
                == expected
        )
    }

    /// `insert` addresses an **insertion point** (`0 ... count`), so `10` is legal
    /// here and `11` is the first invalid one. One shared probe table across all
    /// four cases would be wrong, which is why this is its own test.
    @Test("an out-of-bounds insertion index is rejected", arguments: [-1, 11, Int.min, Int.max])
    func outOfBoundsInsertionIndex(index: Int) {
        let address = Fixtures.at(index)
        #expect(
            EditorCore.apply(.insert(.stitch, at: address), to: Fixtures.program)
                == .rejected(.addressOutOfBounds(.brick, at: address))
        )
    }

    /// The boundary asserted from the legal side too. ADR-032 invariant 2's
    /// corollary: a bounds test that only ever asserts `.rejected` passes over an
    /// implementation that rejects *everything*.
    @Test("the last legal index of each case is accepted")
    func lastLegalIndexIsAccepted() {
        let inserted = EditorCore.apply(.insert(.stitch, at: Fixtures.at(10)), to: Fixtures.program)
        if case let .rejected(rejection) = inserted {
            Issue.record("insert at 10 (== count) should be legal, got \(rejection)")
        }
        let deleted = EditorCore.apply(.delete(at: Fixtures.at(9)), to: Fixtures.program)
        if case let .rejected(rejection) = deleted {
            Issue.record("delete at 9 (== count − 1) should be legal, got \(rejection)")
        }
    }

    /// A `BrickAddress` has **four** independently-resolvable components, so
    /// "out of bounds" without a discriminator is ambiguous. Each hop is asserted
    /// separately: a single collapsed `guard` over all four would otherwise
    /// satisfy a test that only checked for *some* rejection.
    /// Swept over `AddressComponent.allCases` rather than a hand-listed table, so
    /// a fifth hop cannot be added without a test — the same friction
    /// `BrickKind.allCases` already buys elsewhere. The builder's switch is
    /// exhaustive with no `default:`, so the compile error arrives there first.
    @Test("each address component reports itself when it is the one out of bounds",
          arguments: AddressComponent.allCases)
    func eachComponentIsDiscriminated(component: AddressComponent) {
        let address = Self.addressOutOfBounds(at: component)
        #expect(
            EditorCore.apply(.delete(at: address), to: Fixtures.program)
                == .rejected(.addressOutOfBounds(component, at: address))
        )
    }

    /// An address that is out of bounds at **exactly** `component` and valid at
    /// every other hop. The fixture's real script is scene 1 / object 2 /
    /// script 1, with 2 scenes, 3 objects, 2 scripts and 10 bricks.
    private static func addressOutOfBounds(at component: AddressComponent) -> BrickAddress {
        var script = Fixtures.address
        var brickIndex = 0
        switch component {
        case .scene: script.sceneIndex = 2
        case .object: script.objectIndex = 3
        case .script: script.scriptIndex = 2
        case .brick: brickIndex = 10
        }
        return BrickAddress(brickIndex: brickIndex, script: script)
    }

    /// Resolution is outside-in, so an address that is wrong at several hops
    /// reports the **outermost** one. Pinned because the payload is asserted by
    /// exact value everywhere else, and a resolver that checked the brick index
    /// first would answer `.brick` for all of these.
    @Test("an address wrong at several hops reports the outermost")
    func resolutionIsOutsideIn() {
        let address = BrickAddress(
            brickIndex: 99,
            script: ScriptAddress(sceneIndex: 9, objectIndex: 9, scriptIndex: 9)
        )
        #expect(
            EditorCore.apply(.delete(at: address), to: Fixtures.program)
                == .rejected(.addressOutOfBounds(.scene, at: address))
        )
    }

    /// Negative components at every hop, on the empty program that has no valid
    /// index anywhere. Nothing here should be reachable; the test exists so that
    /// if any of it *is* reachable, it fails instead of trapping.
    @Test("nothing traps on an empty program", arguments: [-1, 0, Int.min, Int.max])
    func nothingTrapsOnAnEmptyProgram(index: Int) {
        let empty = Program()
        let address = BrickAddress(
            brickIndex: index,
            script: ScriptAddress(sceneIndex: index, objectIndex: index, scriptIndex: index)
        )
        let actions: [EditAction] = [
            .insert(.stitch, at: address),
            .delete(at: address),
            .move(from: address, to: index),
            .replaceBrick(at: address, with: .stitch),
            .renameProgram("still fine")
        ]
        for action in actions {
            // Calling it at all is the assertion: a trap aborts the process.
            _ = EditorCore.apply(action, to: empty)
        }
        #expect(
            EditorCore.apply(.delete(at: address), to: empty)
                == .rejected(.addressOutOfBounds(.scene, at: address))
        )
    }

    /// The destination half of item 9. `.destinationOutOfBounds` carries the
    /// index rather than a component, because a destination has only one.
    ///
    /// Swept over **both source kinds**, which is the point: the leaf path bounds
    /// its destination in `EditorCore` and the pair path learns it from
    /// `movingPair`, so a probe from one source says nothing about the other.
    /// This originally ran from the leaf alone, and `swift-code-reviewer` found
    /// the gap as a surviving mutant — clamping the pair path's destination with
    /// `max(0, destination)` silently relocated a loop to the front of the script
    /// and left the whole suite green. Item 9 asks for "`Int.max` and a negative
    /// index"; the negative half was reaching only one of the two paths.
    @Test("an out-of-range move destination is rejected on both source kinds",
          arguments: [-1, 10, Int.min, Int.max], [0, 1])
    func outOfRangeDestination(destination: Int, source: Int) {
        #expect(
            EditorCore.apply(.move(from: Fixtures.at(source), to: destination), to: Fixtures.program)
                == .rejected(.destinationOutOfBounds(index: destination))
        )
    }
}
