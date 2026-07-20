/// What triggers a script to run (Catroid `Script` subclasses). M2 ships only
/// `.whenStarted` — Catroid's `StartScript`, whose `WhenStartedBrick` header
/// contributes no action. An enum so later milestones add trigger cases (e.g.
/// tap, message received) without reshaping the model.
public enum ScriptHeader: Sendable, Equatable, Codable {
    case whenStarted
}
