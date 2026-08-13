// `Observation`, not `SwiftUI`: the model is the app's state, and nothing here
// needs a view type. Keeping SwiftUI out of this file is what lets the tests
// exercise it as a plain object.
import EmbroideryEngine
import Interpreter
import Observation
import Samples
import StagePreview

/// The app's state above the navigation containers: what can be picked, what is
/// picked, and how deep the compact stack is.
///
/// One instance per window, owned by `WindowRootView` — not by the `App`, whose
/// state every scene would share. See that view for why; the short version is
/// that this app supports multiple iPad windows, and a selection is a per-window
/// decision.
///
/// **Owning this above `RootView` is what stops the size-class swap discarding
/// the selection** — deliberately not "lossless", which an earlier version of
/// this comment claimed three lines above a list of things it does lose,
/// and it is the fix US-303 deferred to this story by name (`RootView`'s own doc
/// comment, and ADR-023). `RootView` branches on the horizontal size class and
/// swaps one navigation container for another, tearing down whichever it leaves;
/// anything either container owned goes with it. Until now that cost only a
/// scroll position, because there was nothing to select. There is now.
///
/// What survives an iPad window resize across the boundary: the selection —
/// identity *and* generation — and the compact stack depth. What honestly does
/// not, listed rather than glossed:
///
/// - scroll position in the list and in the detail column, which SwiftUI owns
///   inside the container being destroyed;
/// - `NavigationSplitViewVisibility`, which resets to `.automatic`. Hoistable in
///   one property and deliberately not hoisted: `.automatic` is the right state
///   on re-entry, so the property would exist only to be preserved;
/// - in-flight transitions across the swap.
@MainActor
@Observable
final class AppModel {
    /// What the picker lists.
    ///
    /// A pass-through today, and the single seam M5 replaces when the real
    /// project list arrives (create/rename/duplicate/delete). Routing the view
    /// through it rather than letting the view read `SampleLibrary.all` directly
    /// is the entire reason M5 is an edit here instead of an edit to the view.
    var samples: [SampleProgram] {
        SampleLibrary.all
    }

    /// The chosen sample, or `nil` before the first tap.
    ///
    /// `private(set)` so every mutation goes through `select(_:)` and the
    /// generation can never be skipped — an assignment that bypassed it would
    /// reintroduce exactly the no-op this story exists to forbid.
    private(set) var selection: SampleSelection?

    /// The compact navigation stack's path.
    ///
    /// `var`, because `NavigationStack(path:)` writes back on Back and on the
    /// interactive swipe. A typed array rather than `NavigationPath` because a
    /// test can assert the whole value — `NavigationPath` is `Equatable` too, so
    /// the reason is readability of its *contents*, not equality, which an
    /// earlier version of this comment got wrong.
    ///
    /// It is an unrestricted `var`, so the invariant "a non-empty path implies a
    /// selection" is upheld by there being exactly one writer today
    /// (`select(_:)`) and not by the type. A later story that pushes `.stage`
    /// without selecting — a deep link, state restoration — would reach a stage
    /// titled "Stage" showing the empty state. Worth encoding when there is a
    /// second writer; not worth the binding machinery while there is one.
    var path: [StageDestination] = []

    /// `@ObservationIgnored` on purpose: bumping the counter is bookkeeping, not
    /// state anyone renders, and the attribute keeps it out of the observation
    /// graph entirely.
    ///
    /// It is **not** what keeps `select(_:)` to a single notification, which an
    /// earlier version of this comment claimed. Observation is keypath-granular,
    /// so an un-ignored counter would notify only observers that had *read* it,
    /// and nothing reads it — it is `private`. And `select(_:)` mutates two
    /// observed properties anyway (`selection` and `path`), so the "exactly one
    /// observable mutation" discipline US-306 is held to is not a property this
    /// class has ever had. (In-loop review.)
    @ObservationIgnored private var nextGeneration = 0

    /// Selects `sample` and shows the stage.
    ///
    /// Never a no-op, even for the sample already selected: the fresh generation
    /// makes the new value unequal to the old one, which is what lets a later
    /// consumer treat any selection as "start over" (US-306).
    ///
    /// The path is **assigned**, not appended to. Appending would stack a second
    /// stage on the first, so Back would return to a stage rather than to the
    /// list.
    ///
    /// It writes `path` even when the split layout is showing, which ignores it.
    /// That is deliberate rather than a leak: it means a window resized down to
    /// compact opens on the design the user had selected, which is how UIKit's
    /// own split-view collapse behaves.
    func select(_ sample: SampleProgram) {
        selection = SampleSelection(sample: sample, generation: nextGeneration)
        nextGeneration += 1
        path = [.stage]
    }

    /// What the stage draws.
    ///
    /// **Temporary, and US-306 deletes this property together with the method below.**
    /// US-305 renders a display list but has no *producer*: the run driver is US-306's,
    /// and it depends on this story for the surface it renders into. Without something
    /// here the new renderer could only ever show the press-play state, so its four
    /// definition-of-done screenshots would evidence an empty hoop and ADR-009's whole
    /// rendering strategy would reach `main` never having drawn a stitch on a device.
    /// Sebastian's call, recorded in the story under "Scope decisions".
    private(set) var display = StitchDisplayList()

    /// Bounds the temporary drain below. M3's bundled samples finish in far fewer ticks
    /// than this; the cap exists so a future sample with an unbounded loop cannot hang
    /// the main actor rather than because any real number was chosen.
    @ObservationIgnored private static let previewTickCap = 20000

    /// Runs the selected sample to completion, synchronously, and keeps every stitch.
    ///
    /// **This is not what US-306 will do, and the differences are the point of the note.**
    /// It runs to completion instead of one tick per frame, so nothing animates; it runs
    /// on the main actor, which US-306 must not do because a single `step()` can emit
    /// millions of events; and it has no run state, so there is nothing to start, stop or
    /// report. It exists only so this story's renderer can be *seen*.
    ///
    /// It does honour two things that are not temporary, because getting them wrong here
    /// would mislead the next story: events are folded through `RunBatch.reducing` rather
    /// than read directly (so the app performs none of ADR-015's colour reasoning), and
    /// the display list is appended to rather than rebuilt, which is what keeps
    /// ADR-021's append-only prefix intact.
    ///
    /// `settledCount` is deliberately left at zero: advancing the watermark is US-306's
    /// job, and a settling policy invented here would be a second one to unpick.
    func drainSelectionForPreview() {
        display.reset()
        guard let program = selection?.program else { return }

        var interpreter = Interpreter(program: program, clock: AppRunClock.preview)
        var ticks = 0
        while ticks < Self.previewTickCap, case let .ticked(events) = interpreter.step() {
            display.append(contentsOf: RunBatch.reducing(events).stitches)
            ticks += 1
        }
    }

    /// Whether `sample` is the current selection — the row highlight and the
    /// `.isSelected` VoiceOver trait.
    ///
    /// Compares ids, not samples. `SampleProgram`'s synthesized `==` drags the
    /// whole `Program` tree along, and this runs for every row on every body
    /// evaluation.
    func isSelected(_ sample: SampleProgram) -> Bool {
        selection?.sample.id == sample.id
    }
}
