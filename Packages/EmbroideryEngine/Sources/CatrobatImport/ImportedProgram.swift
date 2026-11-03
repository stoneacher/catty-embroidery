import ProgramModel

/// One step of an imported script: a `Brick`, or one of the language tests'
/// harness bricks, which never become `Brick` cases (brief D3), so they cannot
/// reach `BrickKind`, the palette or `ProgramDocument`.
package enum ImportedStep: Sendable, Equatable {
    case brick(Brick)
    /// Catroid `AssertEqualsBrick`; both operands read as assert operands (D4).
    case assertEquals(actual: Formula, expected: Formula)
    /// Catroid `FinishStageBrick`: the test passed.
    case finishStage
    /// Catroid `ExitStageBrick`: the stage ends without a result (D5).
    case exitStage
    /// Catroid `WaitTillIdleBrick` (D8).
    case waitTillIdle
}

/// A StartScript's steps. Every imported script starts when the program does.
package struct ImportedScript: Sendable, Equatable {
    package var steps: [ImportedStep]

    package init(steps: [ImportedStep]) {
        self.steps = steps
    }
}

package struct ImportedObject: Sendable, Equatable {
    package var name: String
    package var variables: [Variable]
    package var scripts: [ImportedScript]

    package init(name: String, scripts: [ImportedScript], variables: [Variable] = []) {
        self.name = name
        self.variables = variables
        self.scripts = scripts
    }
}

/// A `code.xml`'s first and only scene, mirroring `Program` with harness steps.
package struct ImportedProgram: Sendable, Equatable {
    package var name: String
    package var sceneName: String
    package var variables: [Variable]
    package var objects: [ImportedObject]

    package init(objects: [ImportedObject], name: String = "", sceneName: String = "", variables: [Variable] = []) {
        self.name = name
        self.sceneName = sceneName
        self.variables = variables
        self.objects = objects
    }

    /// The program without harness steps, for an app import; one with any is
    /// refused. Every object starts at (0, 0) facing 90, where Catroid starts a
    /// look (`content/Look.java:88`), in list order.
    package func program() throws(CatrobatImportError) -> Program {
        var harness = false
        let objects = objects.enumerated().map { index, object in
            Object(
                name: object.name, startX: 0, startY: 0, startHeading: 90, zIndex: index,
                variables: object.variables,
                scripts: object.scripts.map { script in
                    Script(header: .whenStarted, bricks: script.steps.compactMap { step in
                        guard case let .brick(brick) = step else {
                            harness = true
                            return nil
                        }
                        return brick
                    })
                }
            )
        }
        guard !harness else { throw CatrobatImportError(blockers: [.harnessStep]) }
        return Program(name: name, scenes: [Scene(name: sceneName, objects: objects)], variables: variables)
    }
}

/// Every reason a `code.xml` could not be imported (brief D7: all of them, not
/// the first).
package struct CatrobatImportError: Error, Equatable {
    package var blockers: Set<ImportBlocker>

    package init(blockers: Set<ImportBlocker>) {
        self.blockers = blockers
    }
}
