import Samples
import SwiftUI

/// The app's root, adaptive by size class from the start (ADR-010).
///
/// Compact reaches the stage sequentially through a `NavigationStack`; regular
/// shows the list and the stage side by side with the stage on the **detail**
/// side. Deciding this now rather than "adding iPad support later" is the ADR's
/// whole point — retrofitting a split layout onto a stack-shaped app means
/// rewriting the navigation model, not adding a branch.
///
/// **Skeleton fidelity only.** There is no selection, no editor and no run
/// control here: US-304 owns picking a sample, US-305 the renderer, US-306 the
/// run lifecycle. What this story owns is that the shell exists, adapts, is
/// localized, and genuinely links the engine.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .compact {
            NavigationStack {
                sampleList
                    .navigationTitle(Text(.rootTitle))
                    .navigationDestination(for: StageDestination.self) { _ in
                        StagePlaceholderView()
                    }
            }
        } else {
            NavigationSplitView {
                sampleList
                    .navigationTitle(Text(.rootTitle))
            } detail: {
                StagePlaceholderView()
            }
        }
    }

    /// The bundled samples, in `SampleLibrary.all`'s presentation order.
    ///
    /// A private computed property rather than its own type: US-304 replaces
    /// this body with `SamplePickerView` and adds the selection model, so giving
    /// it a name now would create a type that exists only to be deleted.
    ///
    /// Rows carry no `NavigationLink` — a row that navigates *is* selection, and
    /// selection is US-304's. Compact reaches the stage through the separate
    /// link below, which keeps "sequential navigation works" provable today
    /// without inventing a selection model this story would have to unpick.
    private var sampleList: some View {
        List {
            Section {
                ForEach(SampleLibrary.all) { sample in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sample.displayName)
                            .font(.headline)
                        Text(sample.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(.rootSamplesHeader)
            }

            if horizontalSizeClass == .compact {
                Section {
                    NavigationLink(value: StageDestination.stage) {
                        Text(.stageTitle)
                    }
                }
            }
        }
    }
}

/// The single navigation destination the skeleton has.
///
/// A named type rather than a `Bool` or the sample itself, because
/// `navigationDestination(for:)` keys on the type: when US-304 pushes a chosen
/// sample and US-306 adds a run, each gets its own case here rather than
/// overloading one flag.
enum StageDestination: Hashable {
    case stage
}

#Preview("Compact") {
    RootView()
        .environment(\.horizontalSizeClass, .compact)
}

#Preview("Regular") {
    RootView()
        .environment(\.horizontalSizeClass, .regular)
}
