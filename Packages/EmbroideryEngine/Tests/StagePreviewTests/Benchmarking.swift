import Foundation

// Timing helpers for US-309's headless guards. Free functions, like `PreviewFixtures`,
// so no one suite's `type_body_length` pays for them.

/// The fastest of `attempts` runs, after one discarded warm-up — **abandoned as soon as a
/// single run exceeds `budget`**.
///
/// **Fastest rather than mean.** A wall-clock measurement in a parallel test suite is
/// contaminated only *upwards* — by other tests on other cores, by the scheduler, by a
/// thermal event — never downwards. The minimum is therefore the closest estimate of the
/// work itself this environment can produce, and it is what makes the ratios below survive a
/// loaded CI machine. A mean would import every other suite's noise into this one's
/// assertion. The warm-up is discarded because the first run pays for page faults, lazy
/// metadata and a cold allocator — real costs, paid once, and not the per-element cost under
/// test.
///
/// **The budget is not an optimisation; it is what stops the guard wedging the commit
/// gate.** Measured against a deliberately quadratic `append`: `.timeLimit` records an issue
/// at its deadline (`Time limit was exceeded: 60.000 seconds`) but **cannot cancel a
/// synchronous test body**, so the mutant kept running for more than ten further minutes
/// with the failure already recorded. On the pre-commit gate that is a hang, not a red. With
/// a budget, a regression is abandoned after one over-long run and the assertion fails on
/// the measurement it did manage to take — which is also why the anchors below are sized so
/// that a *single* quadratic run is tolerable.
func fastest(
    of attempts: Int = 5, within budget: Duration = .milliseconds(500), _ body: () -> Void
) -> Duration {
    let clock = ContinuousClock()

    // Timed, unlike an ordinary warm-up, precisely so a pathological implementation is
    // abandoned here rather than five runs later.
    let warmUpStart = clock.now
    body()
    let warmUp = clock.now - warmUpStart
    if warmUp > budget { return warmUp }

    var best: Duration?
    for _ in 0 ..< attempts {
        let start = clock.now
        body()
        let elapsed = clock.now - start
        if best == nil || elapsed < best! {
            best = elapsed
        }
        if elapsed > budget { break }
    }
    // `attempts` is a literal at every call site, so the nil case is unreachable; the
    // coalesce keeps it unreachable by construction rather than by call-site discipline.
    return best ?? warmUp
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
