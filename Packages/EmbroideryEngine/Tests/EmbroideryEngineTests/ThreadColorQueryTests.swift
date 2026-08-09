import EmbroideryEngine
import Testing

/// `threadColor(for:)` — the read-only view of ADR-015 colour state that
/// ADR-021 adds so `InterpreterEvent.stitch` can carry a resolved colour.
///
/// The invariant these tests exist for is **order-insensitivity across
/// `addStitch`**. It is what makes the producer change a single read rather
/// than a refactor, and it holds for a structural reason rather than by luck:
/// `addStitch` snapshots `colorState.current` before any clause runs and
/// afterwards only ever clears `pendingChange`. A test that only checked the
/// value *after* a stitch would pass against an implementation that resolved
/// the colour lazily and got the clause-A case wrong.
@Suite("Thread color query")
struct ThreadColorQueryTests {
    private let actor = ActorID(0)
    private let otherActor = ActorID(1)
    private let red = ThreadColor(red: 255, green: 0, blue: 0)
    private let green = ThreadColor(red: 0, green: 255, blue: 0)
    private let origin = StagePoint(x: 0, y: 0)

    @Test("an actor that never set a color reads black, matching ColorState's own default")
    func unknownActorReadsBlack() {
        let manager = EmbroideryPatternManager()
        #expect(manager.threadColor(for: actor) == .black)
    }

    @Test("reading before and after addStitch yields the same color")
    func orderInsensitiveAcrossAddStitch() {
        var manager = EmbroideryPatternManager()
        manager.setThreadColor(red, for: actor)

        let before = manager.threadColor(for: actor)
        manager.addStitch(at: origin, layer: 0, actor: actor)
        let after = manager.threadColor(for: actor)

        #expect(before == red)
        #expect(after == red)
    }

    /// Clause A returns early, before the clause chain and before
    /// `pendingChange` is cleared — the one `addStitch` path that skips almost
    /// the whole method. The colour must be unaffected there too, or the
    /// producer's read would depend on whether the stitch happened to dedup.
    @Test("a clause-A deduped addStitch leaves the color untouched")
    func orderInsensitiveAcrossADedupedStitch() {
        var manager = EmbroideryPatternManager()
        manager.setThreadColor(red, for: actor)
        manager.addStitch(at: origin, layer: 0, actor: actor)

        let before = manager.threadColor(for: actor)
        manager.addStitch(at: origin, layer: 0, actor: actor) // same point, same actor
        #expect(manager.threadColor(for: actor) == before)
        #expect(manager.threadColor(for: actor) == red)
    }

    @Test("each actor carries its own color")
    func colorIsPerActor() {
        var manager = EmbroideryPatternManager()
        manager.setThreadColor(red, for: actor)
        manager.setThreadColor(green, for: otherActor)

        #expect(manager.threadColor(for: actor) == red)
        #expect(manager.threadColor(for: otherActor) == green)
    }

    /// ADR-015's invalid-hex rule, observed through the new accessor: the
    /// malformed set is a full no-op, so a consumer reading this value inherits
    /// the rule instead of re-implementing it.
    @Test("a malformed hex leaves the current color unchanged")
    func invalidHexLeavesColorUnchanged() {
        var manager = EmbroideryPatternManager()
        manager.setThreadColor(red, for: actor)
        manager.setThreadColor(hexString: "not-a-color", for: actor)
        #expect(manager.threadColor(for: actor) == red)
    }

    /// The silent start (ADR-015): setting a colour before anything is emitted
    /// chooses block 1's colour and arms no change record. The accessor must
    /// report the chosen colour either way — the armed bit is deliberately not
    /// observable through it.
    @Test("a color set before any emission is still the color that is read back")
    func silentStartIsVisibleToTheReader() {
        var manager = EmbroideryPatternManager()
        manager.setThreadColor(red, for: actor)
        #expect(manager.threadColor(for: actor) == red)
        #expect(manager.assembled().colorChangeCount == 0)
    }
}
