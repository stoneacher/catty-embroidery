import SwiftUI

@main
struct CatrobatEmbroideryApp: App {
    var body: some Scene {
        WindowGroup {
            WindowRootView()
        }
    }
}

/// One window's root, and the owner of that window's state.
///
/// The `AppModel` lives **here** rather than as `@State` on the `App`, and the
/// difference is not organisational. State declared on an `App` is created once
/// and shared by every scene it produces, and this app ships with
/// `UIApplicationSupportsMultipleScenes = true` (the generated Info.plist,
/// verified in the built product) — so on iPad a user can open a second window.
/// With App-scoped state, selecting a design in window A would move window B:
/// B's detail column would change design, a B that was sitting on the picker
/// would navigate to the stage, and Back in one window would clear the other's
/// path. None of that follows any action the second window's user took. It also
/// gets worse in US-306, where a selection *restarts a run* — two windows would
/// restart each other.
///
/// A view inside the `WindowGroup` is instantiated once per scene, so each
/// window gets its own model and the windows are independent. (Cross-vendor
/// review, round 1.)
///
/// It still satisfies what ADR-023 actually requires — that the model be owned
/// **above `RootView`**, outside the size-class branch that swaps one navigation
/// container for another and destroys whichever it leaves. This view holds the
/// state; `RootView` below it holds the branch.
///
/// The model is injected explicitly rather than through `.environment(_:)`,
/// because a missing `@Environment(AppModel.self)` is a *runtime* crash where a
/// missing initializer argument is a compile error. For a target whose local
/// gate compiles but does not run (ADR-023), compile-time is the gate that
/// actually fires. (The earlier justification also claimed the chain was "one
/// level deep". It is three — this view, `RootView`, then the picker and the
/// stage — and the argument never needed the depth claim.)
struct WindowRootView: View {
    @State private var model = AppModel()

    var body: some View {
        RootView(model: model)
    }
}
