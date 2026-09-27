import ProgramModel

public extension Program {
    /// The program the editor starts from when nothing has been picked (US-405, ADR-038):
    /// one scene, one object, one empty `whenStarted` script — the least a user can add a
    /// brick to.
    ///
    /// - **The needle faces right (`startHeading: 90`)**, which is Catroid's default and what
    ///   Octagon Rosette stores. Under ADR-007 0° is *up*, and `Object`'s own default is 0 —
    ///   the easy value to leave in by accident, and the reason `BlankProgramTests` pins the
    ///   heading by itself.
    /// - **The program's name is empty.** It is persisted (US-406), so an English word here
    ///   would reach disk and never be localised. The scene and object names are Catroid's
    ///   defaults and what both shipping samples store; nothing in M4 shows them.
    ///
    /// Here rather than in the app so it runs on the fast `swift test` gate and so US-406's
    /// store and US-411's totality proof can reach it. A computed property over a `let` only
    /// because it is a value: every read is a fresh copy either way.
    static var blank: Program {
        Program(
            name: "",
            scenes: [Scene(name: "Scene 1", objects: [
                Object(name: "Needle", startHeading: 90, scripts: [Script(header: .whenStarted)])
            ])]
        )
    }
}
