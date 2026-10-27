import Foundation

/// The project the user last opened, across launches (brief D6): what a window opens when its
/// scene has no project of its own, as after a force-quit.
///
/// A reference type over `UserDefaults`, injected, so tests use a disposable suite rather than
/// the app's defaults. App-scoped like the library that owns it: every window's opening and
/// first save writes it.
@MainActor
public final class LastOpenedProject {
    /// The defaults key. Its value is the ID's UUID string.
    static let key = "lastOpenedProjectID"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Read defensively: anything under the key that is not a UUID string reads as `nil`.
    public var id: ProjectID? {
        get { ProjectID(uuidString: defaults.string(forKey: Self.key)) }
        set {
            if let newValue {
                defaults.set(newValue.uuidString, forKey: Self.key)
            } else {
                defaults.removeObject(forKey: Self.key)
            }
        }
    }

    /// Stops remembering `id`, if it is the one remembered (a deleted project, D9).
    func forget(_ id: ProjectID) {
        if self.id == id {
            self.id = nil
        }
    }
}
