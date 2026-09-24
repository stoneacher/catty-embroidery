import EditorCore
import ProgramModel

/// Shared, immutable fixtures for US-402's suites, plus the deterministic
/// generator the balance property runs on.
///
/// Everything is `static let`. `EditorCoreTests` runs in parallel, so a shared
/// `var` would be a data race and a non-reproducible fixture; the generator is
/// a value type instantiated inside each test.
enum EditorCoreFixtures {
    // MARK: The decoy-shaped program

    /// Where the interesting script lives: **scene 1, object 2, script 1**.
    ///
    /// Every component is a *different* number and every collection a different
    /// size, which is the whole point. `EditorAddressTests` adopted this shape
    /// after Codex round 2 showed a transposed initializer (`self.sceneIndex =
    /// objectIndex`) survived a fixture that used `1` for all three components.
    /// US-402 is the first story to **write back** through an address, so the
    /// same defeat is available again and in a place the read-only traversal
    /// never covered: a write-back that resolves the right script and stores
    /// into the wrong one passes every one-scene/one-object/one-script fixture.
    static let address = ScriptAddress(sceneIndex: 1, objectIndex: 2, scriptIndex: 1)

    /// The script every addressed test edits. Deliberately shaped for the plan:
    ///
    /// ```
    /// 0  moveNSteps(1)      leaf before
    /// 1  repeatLoop(2)      opener A  ─┐  a loop with a three-brick body,
    /// 2    stitch            │         │  so test 4's "removes five elements"
    /// 3    turnRight(3)      │         │  is arithmetic rather than a
    /// 4    sewUp             │         │  restatement of the fixture
    /// 5  loopEnd            end A     ─┘
    /// 6  forever            opener B  ─┐  a *sibling* loop, so test 6 moves a
    /// 7    changeXBy(4)      │         │  pair over a pair rather than over a
    /// 8  loopEnd            end B     ─┘  leaf
    /// 9  stopRunningStitch  leaf after
    /// ```
    ///
    /// Every brick carries a distinct payload where it has one, so a transposed
    /// or off-by-one edit lands on a value that differs rather than on a
    /// look-alike.
    static let bricks: [Brick] = [
        .moveNSteps(.number(1)),
        .repeatLoop(times: .number(2)),
        .stitch,
        .turnRight(.number(3)),
        .sewUp,
        .loopEnd,
        .forever,
        .changeXBy(.number(4)),
        .loopEnd,
        .stopRunningStitch
    ]

    /// A balanced program whose scene/object/script indices are all distinct,
    /// with decoys at every hop that would be hit by a swapped component.
    static let program = Program(
        name: "editor fixture",
        scenes: [
            Scene(name: "decoy scene", objects: [
                Object(name: "decoy", scripts: [Script(bricks: [.stitch])])
            ]),
            Scene(name: "real", objects: [
                Object(name: "decoy 0", scripts: [Script(bricks: [.sewUp])]),
                Object(name: "decoy 1", scripts: [
                    Script(bricks: [.stitch, .stitch]),
                    Script(bricks: [.stitch, .stitch, .stitch])
                ]),
                Object(name: "real", scripts: [
                    Script(bricks: [.stopRunningStitch]),
                    Script(bricks: bricks)
                ])
            ])
        ],
        variables: [Variable(name: "Side", value: 5)]
    )

    /// A `BrickAddress` into the fixture's real script.
    static func at(_ brickIndex: Int) -> BrickAddress {
        BrickAddress(brickIndex: brickIndex, script: address)
    }

    /// The fixture with its real script's bricks replaced — the expectation
    /// builder for the whole-`Program` assertions (ADR-006 pattern 3). Written
    /// as a transformation of `program` rather than as a second literal so an
    /// expectation cannot silently disagree with the fixture about the decoys.
    static func expecting(_ newBricks: [Brick]) -> Program {
        var expected = program
        expected.scenes[address.sceneIndex]
            .objects[address.objectIndex]
            .scripts[address.scriptIndex]
            .bricks = newBricks
        return expected
    }

    /// The real script as it currently stands.
    static var script: Script {
        program.scenes[address.sceneIndex]
            .objects[address.objectIndex]
            .scripts[address.scriptIndex]
    }

    // MARK: Malformed programs

    /// A program with a **bare `loopEnd`** in scene 0 / object 0 / script 0 and
    /// a balanced script beside it at script index 1.
    ///
    /// Unreachable through `EditAction` by construction (ADR-035), which is
    /// exactly why it has to be built by hand: the preservation half of the
    /// balance criterion is a claim about programs `apply` did not create, and
    /// until US-404 gains its admission check a decoded document can be one.
    static let withStrayLoopEnd = Program(
        name: "malformed",
        scenes: [
            Scene(name: "only", objects: [
                Object(name: "only", scripts: [
                    Script(bricks: [.loopEnd]),
                    Script(bricks: [.stitch, .forever, .sewUp, .loopEnd])
                ])
            ])
        ]
    )

    /// The address of the balanced script sitting beside the stray `loopEnd`.
    static let balancedScriptBesideTheStrayEnd = ScriptAddress(scriptIndex: 1)

    /// A program whose only script is `[repeatLoop(2), moveNSteps(10)]` — an
    /// opener that is never closed. Test 10c's fixture: this is the shape on
    /// which `move` **must** stay rejected.
    static let withUnclosedOpener = Program(
        name: "unclosed",
        scenes: [
            Scene(name: "only", objects: [
                Object(name: "only", scripts: [
                    Script(bricks: [.repeatLoop(times: .number(2)), .moveNSteps(.number(10))])
                ])
            ])
        ]
    )

    // MARK: The generator

    /// A small balanced program for the property test — one scene, one object,
    /// one script, because the property is about brick-list balance and the
    /// addressing decoys would only slow the traversal down.
    static let propertySeed = Program(
        name: "seed",
        scenes: [
            Scene(name: "only", objects: [
                Object(name: "only", scripts: [
                    Script(bricks: [
                        .stitch,
                        .repeatLoop(times: .number(3)),
                        .moveNSteps(.number(10)),
                        .forever,
                        .sewUp,
                        .loopEnd,
                        .loopEnd,
                        .stopRunningStitch
                    ])
                ])
            ])
        ]
    )

    /// One random action against the program **as it currently stands**.
    ///
    /// Adaptive rather than blind, and that is not a nicety: with a fixed index
    /// range, a few applied deletes leave almost every later action rejected,
    /// and the invariant — which is a claim about the **applied** path — stops
    /// being exercised while the test still passes. The non-vacuity assertions
    /// in the property test are what prove this generator did not degenerate.
    ///
    /// Roughly one index in eight is deliberately out of bounds, so the totality
    /// path is walked too.
    static func randomAction(
        against program: Program,
        using generator: inout SplitMix64
    ) -> EditAction {
        let script = program.scenes[0].objects[0].scripts[0]
        let count = script.bricks.count
        let address = BrickAddress(brickIndex: index(upTo: count, using: &generator))

        switch generator.next() % 5 {
        case 0:
            return .insert(BrickKind.allCases.randomElement(using: &generator)!, at: address)
        case 1:
            return .delete(at: address)
        case 2:
            // The destination range depends on the *span* of the block being
            // moved — `0 ... (count − span)` — so sampling it from `0 ... count`
            // rejects most pair moves out of hand. One seed recorded zero applied
            // pair relocations because of it. Asking the model for the span is
            // what "adaptive rather than blind" already means here; the
            // out-of-bounds tail still fires through `index(upTo:)`.
            let span = script.range(ofPairAt: address.brickIndex)?.count ?? 1
            return .move(from: address, to: index(upTo: max(0, count - span), using: &generator))
        case 3:
            // Same kind most of the time, so the parameter-edit path actually
            // applies; a different kind sometimes, so the guard is walked.
            //
            // The same-kind replacement is `perturbed(_:)`, **not** the kind's
            // own `template()`. Codex round 1's strengthened non-vacuity floors
            // showed why: every brick a generated run inserts comes *from*
            // `template()`, so replacing one with its template is a no-op, and all
            // three seeds recorded **zero** applied replacements while the old
            // floors reported coverage.
            let inBounds = script.bricks.indices.contains(address.brickIndex)
            let replacement: Brick = if !inBounds || generator.next() % 4 == 0 {
                BrickKind.allCases.randomElement(using: &generator)!.template()[0]
            } else {
                perturbed(script.bricks[address.brickIndex])
            }
            return .replaceBrick(at: address, with: replacement)
        default:
            return .renameProgram("name \(generator.next() % 1000)")
        }
    }

    /// A brick of the **same kind** carrying a different payload — what a
    /// parameter edit actually looks like (US-410's path).
    ///
    /// Exhaustive with no `default:`, the pattern `BrickKind.init(of:)`
    /// established, so a new `Brick` case is a compile error here rather than a
    /// silent no-op that quietly weakens the property's replacement coverage.
    /// The five payload-free kinds return themselves; the property test's
    /// `before != after` guard then correctly declines to count them.
    static func perturbed(_ brick: Brick) -> Brick {
        switch brick {
        case let .moveNSteps(value): .moveNSteps(bumped(value))
        case let .turnLeft(value): .turnLeft(bumped(value))
        case let .turnRight(value): .turnRight(bumped(value))
        case let .pointInDirection(value): .pointInDirection(bumped(value))
        // Two slots, two **different** values — see `bumped(_:salt:)`.
        case let .placeAt(x, y): .placeAt(x: bumped(x), y: bumped(y, salt: 7))
        case let .setX(value): .setX(bumped(value))
        case let .setY(value): .setY(bumped(value))
        case let .changeXBy(value): .changeXBy(bumped(value))
        case let .changeYBy(value): .changeYBy(bumped(value))
        case let .repeatLoop(times): .repeatLoop(times: bumped(times))
        case .forever: .forever
        case .loopEnd: .loopEnd
        case let .wait(seconds): .wait(seconds: bumped(seconds))
        case let .setVariable(name, to): .setVariable(name: toggled(name), to: bumped(to))
        case let .changeVariableBy(name, value):
            .changeVariableBy(name: toggled(name), value: bumped(value))
        case .stitch: .stitch
        // Upper-case on purpose, for the same reason the variable names are mixed
        // case: `Brick.setThreadColor` stores an unrestricted `String`, and
        // nothing at this boundary canonicalises it, so an unwanted
        // `.lowercased()` here should be visible through whole-`Program`
        // equality (Codex round 3).
        case let .setThreadColor(hex): .setThreadColor(hex: hex == "#00FF00" ? "#0000FF" : "#00FF00")
        case let .runningStitch(length): .runningStitch(length: bumped(length))
        case let .zigZagStitch(length, width):
            .zigZagStitch(length: bumped(length), width: bumped(width, salt: 7))
        case let .tripleStitch(length): .tripleStitch(length: bumped(length))
        case .sewUp: .sewUp
        case .stopRunningStitch: .stopRunningStitch
        case let .writeEmbroideryToFile(name):
            .writeEmbroideryToFile(name: name == "Design A.dst" ? "Design B.dst" : "Design A.dst")
        }
    }

    /// A different `Formula`, and a *bounded* one: the property applies hundreds
    /// of actions, so an unbounded `+1` would drift a literal far from anything
    /// the editor can produce and turn a coverage helper into a numeric fuzzer.
    ///
    /// **`salt` is what makes a multi-slot brick discriminating.** The first
    /// version used one constant, so `placeAt(100, 200)` perturbed to
    /// `placeAt(1, 1)` and `zigZagStitch(2, 10)` to `(1, 1)` — equal slots, which
    /// cannot detect a transposition. Codex round 3 found it, and it is the same
    /// defect `EditorAddressTests` fixed after Codex round 2 of US-401: a fixture
    /// whose components share a value proves nothing about which component was
    /// read. Distinct salts per slot; `+ 10` on collision so the result always
    /// differs from the input too.
    private static func bumped(_ formula: Formula, salt: Double = 3) -> Formula {
        guard case let .number(value) = formula else { return .number(salt) }
        return .number(value == salt ? salt + 10 : salt)
    }

    /// Likewise bounded: two names that alternate, never a growing string.
    ///
    /// **Mixed case on purpose.** Codex round 2 showed that lowercase-only names
    /// (`""`, `"a"`, `"b"`) make a payload-mangling mutant invisible — writing
    /// `name.lowercased()` into a `setVariable` replacement changes *which
    /// variable the brick addresses* and leaves every generated action, result
    /// and tally identical. A name that is not already lower-cased is what makes
    /// that mutation observable.
    private static func toggled(_ name: String) -> String {
        name == "Side" ? "Outer Loop" : "Side"
    }

    /// An index in `0 ... count`, with an out-of-bounds tail about one time in
    /// eight.
    private static func index(upTo count: Int, using generator: inout SplitMix64) -> Int {
        if generator.next() % 8 == 0 {
            return [-1, Int.min, Int.max, count + 2].randomElement(using: &generator)!
        }
        return Int(generator.next() % UInt64(count + 1))
    }
}

/// Deterministic generator. Copied from
/// `Tests/EmbroideryEngineTests/TraversalPredicateTests.swift:260` — SwiftPM
/// forbids test→test dependencies, so a shared helper cannot be imported; this
/// is the same response `ByteDiff.swift` already makes to that constraint.
///
/// Conforms to `RandomNumberGenerator`, which the engine copy does not: `next()`
/// already satisfies the requirement verbatim, and the conformance buys
/// `randomElement(using:)` instead of hand-rolled modulo sampling.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
