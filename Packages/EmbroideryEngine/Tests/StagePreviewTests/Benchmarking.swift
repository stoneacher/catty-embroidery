import Foundation

// Timing helpers for US-309's headless guards. Free functions, like `PreviewFixtures`,
// so no one suite's `type_body_length` pays for them.

/// The fastest of `attempts` runs, after one discarded warm-up.
///
/// **Fastest rather than mean, and that is the whole design.** A wall-clock measurement in
/// a parallel test suite is contaminated only *upwards* — by other tests on other cores, by
/// the scheduler, by a thermal event — never downwards. The minimum is therefore the
/// closest estimate of the work itself that this environment can produce, and it is what
/// makes the ratios below survive a loaded CI machine. A mean would import every other
/// suite's noise into this one's assertion.
///
/// The warm-up is discarded because the first run pays for page faults, lazy metadata and
/// a cold allocator — costs that are real, are paid once, and are not the per-element cost
/// under test.
func fastest(of attempts: Int = 5, _ body: () -> Void) -> Duration {
    body()
    var best: Duration?
    for _ in 0 ..< attempts {
        let clock = ContinuousClock()
        let start = clock.now
        body()
        let elapsed = clock.now - start
        if best == nil || elapsed < best! {
            best = elapsed
        }
    }
    // `attempts` is a literal at every call site, so the force-unwrap is unreachable; the
    // nil-coalesce keeps it unreachable *by construction* rather than by call-site
    // discipline.
    return best ?? .zero
}

/// Seconds, as a `Double`, for ratio arithmetic and for failure messages a human can read.
///
/// `Duration` divides only by integers, so a ratio between two durations has to go through
/// a floating-point representation. Attoseconds rather than
/// `Double(components.seconds) + …`: the values here are tens of microseconds, so the
/// whole-second component is always zero and the entire measurement lives in the fraction.
func seconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) * 1e-18
}

/// Milliseconds, rounded for a message.
func milliseconds(_ duration: Duration) -> String {
    String(format: "%.3f ms", seconds(duration) * 1_000)
}
