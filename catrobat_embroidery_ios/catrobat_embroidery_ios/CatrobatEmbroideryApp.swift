import SwiftUI

@main
struct CatrobatEmbroideryApp: App {
    /// The one object here that **is** App-scoped, and the exception is the rule below applied
    /// rather than broken: windows may write the same project files, so the guard deciding
    /// which write wins must see all of them (ADR-037, per project since M5). It holds no
    /// window's program or selection, so sharing it moves nothing one window's user can see in
    /// another.
    @State private var library = ProjectLibrary(
        store: DocumentsProjectStore(), lastOpened: LastOpenedProject(defaults: .standard)
    )

    var body: some Scene {
        WindowGroup {
            WindowRootView(library: library)
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
///
/// **Autosave's window-level wiring lives here too, above the ADR-023 branch**, so a
/// size-class swap can neither re-run the launch nor re-fire the lifecycle save, and
/// the banner and alert survive it (US-406).
struct WindowRootView: View {
    /// `State(initialValue:)` evaluates its argument on every initialisation of this view and
    /// keeps only the first, which is why `AppModel.init` must stay free of side effects and
    /// the launch happens in `onAppear`.
    @State private var model: AppModel

    /// The project this window holds, so a relaunch reopens each window on its own design
    /// (brief D6). Read defensively: a string that names no ID launches as if there were none.
    @SceneStorage("projectID") private var storedProjectID: String?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(library: ProjectLibrary) {
        _model = State(initialValue: AppModel(library: library))
    }

    var body: some View {
        // A `VStack`, not `.safeAreaInset(edge: .top)`: the navigation bar inside `RootView`
        // lays itself out against the window's own safe area, so an outer inset drew the
        // banner *over* the title (seen on the simulator, 2026-09-28). Stacked, the navigation
        // container is laid out below the banner, and the banner's material still extends
        // under the status bar.
        VStack(spacing: 0) {
            if let failure = model.saveFailure {
                AutosaveBanner(failure: failure)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            RootView(model: model)
        }
        .animation(StageMotion.bannerAnimation(reduceMotion: reduceMotion), value: model.saveFailure)
        .alert(
            Text(AutosaveNotice.refusalTitle),
            isPresented: Binding(
                get: { model.launchRefusal != nil },
                set: {
                    if !$0 {
                        model.dismissLaunchRefusal()
                    }
                }
            ),
            presenting: model.launchRefusal,
            // Empty on purpose: the system supplies an OK button in the system language.
            actions: { _ in },
            message: { Text(AutosaveNotice.message(for: $0)) }
        )
        .onAppear {
            // Without animation: on iPhone the launch pushes the stage, and the window should
            // open on it rather than animate there from the picker.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                model.launch(sceneID: ProjectID(uuidString: storedProjectID))
            }
            storedProjectID = model.projectID.uuidString
        }
        .onDisappear {
            model.close()
        }
        .onChange(of: model.projectID) { _, new in
            storedProjectID = new.uuidString
        }
        .onChange(of: scenePhase) { old, _ in
            if old == .active {
                model.sceneDidLeaveActive()
            }
        }
        .onChange(of: model.saveFailure) { old, new in
            announce(new, replacing: old)
        }
    }

    /// Spoken on a transition only, so a window opening onto an existing failure shows the
    /// banner without announcing it. Not while the launch alert is up, which speaks for itself.
    ///
    /// **Known gap**: the failure is per project, so two windows on one project both announce it.
    private func announce(_ failure: ProjectSaveFailure?, replacing old: ProjectSaveFailure?) {
        guard let failure, failure != old, model.launchRefusal == nil else { return }
        AccessibilityNotification.Announcement(String(localized: AutosaveNotice.banner(for: failure)))
            .post()
    }
}
