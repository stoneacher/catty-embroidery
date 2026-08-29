import EmbroideryEngine
import Observation

/// Owns the design's name and the file prepared from it (US-308, ADR-026).
///
/// **Export is eager: the file is written when the run *ends*, not when the user taps
/// share.** Two independent constraints force that, and neither is obvious:
///
/// - A `ShareLink` needs its item at construction time, and it reports failure to the
///   *system* share UI rather than to the app. A write inside the `FileRepresentation`
///   closure would leave `ExportState.failed` with no consumer, and US-211's localised
///   message unreachable behind a generic system alert. Making the overflow a *gate reason*
///   instead is what keeps that message ours.
/// - `Transferable.exported(as:)` — the only way a test can drive a representation — is
///   iOS 18.2+, and this app targets iOS 17. A closure-only write would make the story's
///   own test item 3 unbuildable: a "test that could not fail", arriving through an
///   availability boundary rather than a bad assertion.
///
/// The cost, paid deliberately: one file written per run termination and per committed name
/// change, even for a design nobody shares. It is ~3 ms and one temp file, cleaned up on
/// both sides of its life.
///
/// **Owned by `AppModel`, never `@State` in a view**, for the reason `RunViewModel` and
/// `interaction` are: ADR-023 records that `RootView` swaps one navigation container for
/// another on a horizontal size-class change and tears down whichever it leaves, so a name
/// held in a view would be lost — or, since `RootView` builds the stage at two call sites,
/// would be two different names that disagree.
@MainActor
@Observable
final class ExportViewModel {
    /// What the field holds, raw and unvalidated — bound directly to the `TextField`, so it
    /// must accept anything the user can type. Validation is a *view* of it.
    ///
    /// Editing it **invalidates a prepared file**, because the name goes into the `LA`
    /// bytes: without this, the model can offer `Alpha.dst` while the field reads "Beta",
    /// and the user shares the wrong name *and* the wrong bytes. An in-loop review found
    /// that window open — closed today only by `StageView` hiding the share row while the
    /// field has focus, which is a **view** condition guarding a **model** invariant, and
    /// untested besides.
    var name = "" {
        didSet { discardIfPreparedNameIsStale() }
    }

    private(set) var state: ExportState = .idle

    /// The name the file on disk was actually built from — the only thing that can tell a
    /// prepared file apart from the field's current contents.
    @ObservationIgnored private var preparedName: DesignName?

    @ObservationIgnored private let writer: any DSTFileWriting

    init(writer: any DSTFileWriting = TemporaryDSTFileWriter()) {
        self.writer = writer
    }

    /// The name's verdict, recomputed rather than stored.
    ///
    /// Stored, it would be a second source of truth that a keystroke could leave stale — and
    /// the field's counter, its error line and the share control's hint all read it, so a
    /// stale copy would show three inconsistent things at once. Validation is a handful of
    /// character checks over at most 15 characters.
    var validatedName: Result<DesignName, DesignNameProblem> {
        DesignName.validating(name)
    }

    /// Builds the file for `exportModel` and puts it on disk.
    ///
    /// Called when a run terminates and when a name edit is committed — never per keystroke,
    /// because the name is in the `LA` **bytes** and not only in the file name, so every
    /// commit genuinely invalidates the previous file.
    ///
    /// **The header is built before anything is written**, which is what makes an overflow a
    /// gate reason rather than a failed share. It costs nothing extra: `DSTFile.init` builds
    /// the header anyway, and ADR-025 records that the header is the only part that can fail,
    /// so constructing the file *is* the complete pre-flight check.
    func prepare(exportModel: EmbroideryStream) {
        guard let designName = try? validatedName.get() else {
            // Nothing to name the file after, and the share control is refusing anyway.
            // Deliberately not `.failed`: an unfinished name is not an error to report, it is
            // a field the user is still in the middle of.
            discard()
            return
        }

        let file: DSTFile
        do {
            file = try DSTFile(stream: exportModel, name: designName.value)
        } catch let error as DSTSerializationError {
            state = .failed(.serialization(error))
            return
        } catch {
            state = .failed(.writeFailed)
            return
        }

        // Only now, once there is definitely something to write.
        //
        // **What this ordering buys, stated accurately after an in-loop review corrected it**:
        // no filesystem side effect from a pre-flight rejection — which is what
        // `overflowFailsPreflight`'s `removeAllCount == 0` pins. It does *not* buy "the
        // previous file survives a failure for the user": the file does survive on disk, but
        // `state` is overwritten with `.failed`, so nothing can reach it and it lingers until
        // the next successful `prepare()` or a `discard()`. The property that matters is the
        // one that holds either way — `.ready` and "a file describing this design" cannot come
        // apart, because `removeAll()` always precedes `write` and a throwing write sets
        // `.failed`.
        writer.removeAll()
        do {
            state = try .ready(writer.write(file, named: DSTFileName.sanitising(designName)))
            preparedName = designName
        } catch {
            state = .failed(.writeFailed)
        }
    }

    /// Drops a prepared file the moment the name stops matching it.
    ///
    /// Only from `.ready` — a `.failed` or `.idle` state has nothing to invalidate — so the
    /// repeated keystrokes after the first are a single comparison each.
    private func discardIfPreparedNameIsStale() {
        guard case .ready = state, (try? validatedName.get()) != preparedName else { return }
        discard()
    }

    /// Throws the prepared file away — for a new selection or a discarded run, where the
    /// design on screen is gone and a URL pointing at the old one would be a lie.
    func discard() {
        writer.removeAll()
        state = .idle
        preparedName = nil
    }
}
