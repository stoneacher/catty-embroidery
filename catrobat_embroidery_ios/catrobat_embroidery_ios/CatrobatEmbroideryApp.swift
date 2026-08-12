import SwiftUI

@main
struct CatrobatEmbroideryApp: App {
    /// Owned here, above `RootView`, because `RootView` swaps one navigation
    /// container for another when the size class changes and destroys whichever
    /// it leaves (ADR-023). State that must outlive that swap cannot live
    /// inside either container — and from US-304 on there is a selection to
    /// lose.
    ///
    /// Injected explicitly rather than through `.environment(_:)`: the chain is
    /// one level deep, and a missing `@Environment(AppModel.self)` is a *runtime*
    /// crash where a missing initializer argument is a compile error. For a
    /// target whose local gate compiles but does not run (ADR-023), compile-time
    /// is the gate that actually fires.
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
