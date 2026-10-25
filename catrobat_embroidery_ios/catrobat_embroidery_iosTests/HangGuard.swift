import Testing

/// The time limit for app tests that await the main actor (US-327).
///
/// **A hang guard, not a performance assertion**: it exists so a test that never finishes fails
/// instead of stalling CI. On CI the app suite's main-actor queue reaches about 80 seconds, so a
/// one-minute limit failed tests that were only waiting their turn — four different tests in
/// four runs, a docs-only PR among them (journal, 2026-10-25). Three minutes still fails a hang
/// well inside the job.
extension Trait where Self == TimeLimitTrait {
    static var hangGuard: Self {
        .timeLimit(.minutes(3))
    }
}
