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

    static let program = Program(
        name: "addressing",
        scenes: [
            Scene(name: "first", objects: [Object(name: "only", scripts: [Script(bricks: [.stitch])])]),
            Scene(name: "second", objects: [
                Object(name: "decoy", scripts: [Script(bricks: [.sewUp])]),
                Object(name: "real", scripts: [
                    Script(bricks: [.stitch, .stitch]),
                    Script(bricks: [.moveNSteps(.number(1)), .stitch, target])
                ])
            ])
        ]
    )

    @Test("a brick address reaches its brick through scene, object, script and index")
    func addressReachesItsBrick() {
        let address = BrickAddress(
            script: ScriptAddress(sceneIndex: 1, objectIndex: 1, scriptIndex: 1),
            brickIndex: 2
        )
        let script = Self.program
            .scenes[address.script.sceneIndex]
            .objects[address.script.objectIndex]
            .scripts[address.script.scriptIndex]

        #expect(script.bricks[address.brickIndex] == Self.target)
    }

    /// The zero defaults are what let an ordinary M4 call site read
    /// `BrickAddress(brickIndex: 3)` while the type stays honest against a model
    /// that permits more than one scene.
    @Test("addresses default to the first scene, object and script")
    func addressesDefaultToTheFirstOfEach() {
        #expect(
            BrickAddress(brickIndex: 0)
                == BrickAddress(
                    script: ScriptAddress(sceneIndex: 0, objectIndex: 0, scriptIndex: 0),
                    brickIndex: 0
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
