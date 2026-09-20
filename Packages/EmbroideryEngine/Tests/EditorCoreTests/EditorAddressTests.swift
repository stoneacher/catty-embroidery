import EditorCore
import ProgramModel
import Testing

/// US-401's addressing criterion: a `BrickAddress` reaches a brick through
/// `Program → Scene → Object → Script → index`.
///
/// The story's 7-point test plan has no item for this, so it is added here
/// rather than shipped untested. The fixture is deliberately **not** the
/// one-scene/one-object/one-script shape M4 actually uses: with a 1/1/1
/// program every index field could be ignored and the test would still pass.
@Suite("Editor addressing")
struct EditorAddressTests {
    static let target: Brick = .zigZagStitch(length: .number(4), width: .number(7))

    /// Scene 1, object 2, script 0, brick 3 — every component a **different**
    /// number, which is the point. The first version used `1` for all three
    /// script components, and Codex round 2 showed that a transposed
    /// initializer (`self.sceneIndex = objectIndex`) survived the entire
    /// addressing suite. Distinct values and differing collection sizes mean a
    /// swapped or ignored component indexes out of range or lands on a decoy.
    static let program = Program(
        name: "addressing",
        scenes: [
            Scene(name: "decoy scene", objects: [
                Object(name: "decoy", scripts: [Script(bricks: [.stitch])])
            ]),
            Scene(name: "real", objects: [
                Object(name: "decoy 0", scripts: [Script(bricks: [.sewUp])]),
                Object(name: "decoy 1", scripts: [
                    Script(bricks: [.stitch, .stitch]),
                    Script(bricks: [.stitch, .stitch, .stitch, .stitch])
                ]),
                Object(name: "real", scripts: [
                    Script(bricks: [.moveNSteps(.number(1)), .stitch, .sewUp, target])
                ])
            ])
        ]
    )

    /// Bounds-checked at every hop, so a wrong address **fails** this test
    /// instead of trapping. That is not fastidiousness: the first version
    /// subscripted raw, and when the transposed-initializer mutant was run it
    /// crashed the whole `EditorCoreTests` bundle with "Index out of range" —
    /// taking the other suites' results with it. US-302's red phase recorded the
    /// same lesson: a test that traps hides results rather than reporting one.
    ///
    /// This is a *test* traversal, deliberately not a production resolver. US-402
    /// owns that, together with the out-of-bounds policy ADR-033 makes a
    /// rejection rather than an optional.
    private static func brick(at address: BrickAddress, in program: Program) -> Brick? {
        let script = address.script
        guard program.scenes.indices.contains(script.sceneIndex) else { return nil }
        let objects = program.scenes[script.sceneIndex].objects
        guard objects.indices.contains(script.objectIndex) else { return nil }
        let scripts = objects[script.objectIndex].scripts
        guard scripts.indices.contains(script.scriptIndex) else { return nil }
        let bricks = scripts[script.scriptIndex].bricks
        guard bricks.indices.contains(address.brickIndex) else { return nil }
        return bricks[address.brickIndex]
    }

    @Test("a brick address reaches its brick through scene, object, script and index")
    func addressReachesItsBrick() {
        let address = BrickAddress(
            brickIndex: 3,
            script: ScriptAddress(sceneIndex: 1, objectIndex: 2, scriptIndex: 0)
        )
        #expect(Self.brick(at: address, in: Self.program) == Self.target)
    }

    /// Asserted independently of any traversal, so a transposition inside the
    /// initializer is caught even where the program happens to be shaped such
    /// that the wrong path still resolves.
    @Test("each component is stored in the field it was given to")
    func componentsAreStoredWhereTheyWereGiven() {
        let address = BrickAddress(
            brickIndex: 4,
            script: ScriptAddress(sceneIndex: 1, objectIndex: 2, scriptIndex: 3)
        )
        #expect(address.brickIndex == 4)
        #expect(address.script.sceneIndex == 1)
        #expect(address.script.objectIndex == 2)
        #expect(address.script.scriptIndex == 3)
    }

    /// The zero defaults are what let an ordinary M4 call site read
    /// `BrickAddress(brickIndex: 3)` while the type stays honest against a model
    /// that permits more than one scene.
    @Test("addresses default to the first scene, object and script")
    func addressesDefaultToTheFirstOfEach() {
        #expect(
            BrickAddress(brickIndex: 0)
                == BrickAddress(
                    brickIndex: 0,
                    script: ScriptAddress(sceneIndex: 0, objectIndex: 0, scriptIndex: 0)
                )
        )
    }

    @Test("addresses are Hashable, so they can key editor state")
    func addressesAreHashable() {
        let addresses: Set<BrickAddress> = [
            BrickAddress(brickIndex: 0),
            BrickAddress(brickIndex: 1),
            BrickAddress(brickIndex: 0)
        ]
        #expect(addresses.count == 2)
    }
}
