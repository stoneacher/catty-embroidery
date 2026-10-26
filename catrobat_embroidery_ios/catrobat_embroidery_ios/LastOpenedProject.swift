import Foundation

/// The project the user last opened, across launches (brief D6): what a window opens when its
/// scene has no project of its own, as after a force-quit.
///
/// A reference type over `UserDefaults`, injected, so tests use a disposable suite rather than
/// the app's defaults. App-scoped like the library that owns it: every window's opening and
/// first save writes it.
final class LastOpenedProject {
    /// The defaults key. Its value is the ID's UUID string.
    static let key = "lastOpenedProjectID"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Read defensively: anything under the key that is not a UUID string reads as `nil`.
    var id: ProjectID? {
        get { ProjectID(uuidString: defaults.string(forKey: Self.key)) }
        set {
            if let newValue {
                defaults.set(newValue.uuidString, forKey: Self.key)
            } else {
                defaults.removeObject(forKey: Self.key)
            }
        }
    }
}
