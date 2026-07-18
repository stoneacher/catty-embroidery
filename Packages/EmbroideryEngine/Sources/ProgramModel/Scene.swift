/// A named collection of objects (Catroid `Scene.java`). Scenes hold no
/// variables — variable scope is project- or object-level only.
public struct Scene: Sendable, Equatable, Codable {
    public var name: String
    public var objects: [Object]

    public init(name: String = "", objects: [Object] = []) {
        self.name = name
        self.objects = objects
    }
}
