import CatrobatImport
import Interpreter
import Testing

/// Slice 7 of the language-test runner (brief D12): every one of the 215 Catrobat
/// language tests is imported, run and held to its pinned class, so any change
/// of class is a red test.
struct LanguageTestRunnerTests {
    /// The marker an expected failure's known issue carries, so the matcher accepts
    /// that issue and nothing else.
    private static let pinnedFailure = "language test fails as pinned"

    @Test func everyTestHasExactlyOneExpectation() throws {
        let paths = try LanguageTestCatalog.manifest().tests.map(\.path)
        #expect(Set(LanguageTestExpectation.all.keys) == Set(paths))
        #expect(LanguageTestExpectation.all.count == 215)
    }

    @Test(arguments: LanguageTestCatalog.entries)
    func languageTest(_ entry: LanguageTestManifest.Entry) throws {
        let expectation = try #require(LanguageTestExpectation.all[entry.path], "no expectation for \(entry.path)")
        let imported = try CorpusProgramTests.outcome(of: entry)
        switch expectation {
        case let .unsupported(labels):
            guard case let .failure(error) = imported else {
                Issue.record("\(entry.path) now imports; pin its class")
                return
            }
            #expect(Set(error.blockers.map(\.label)) == labels)

        case .pass:
            let run = try LanguageTestRunner.run(imported.get())
            #expect(run.outcome == .passed, "\(entry.path): \(run.outcome)")
            // Brief D6: a pass needs headroom, so one near the budget is a finding.
            #expect(run.ticks <= Interpreter.harnessBudget / 2, "\(entry.path) took \(run.ticks) ticks")

        case let .expectedFailure(failure, owner):
            let run = try LanguageTestRunner.run(imported.get())
            // Outside any known-issue block: a test that starts failing for another
            // reason (an importer refusal, the budget, another assert) is red here
            // (Codex brief review, finding 2). Such a change reports twice, here and
            // as an unrecorded known issue below: two failures, one cause.
            #expect(run.outcome == .assertionFailed(failure), "\(entry.path): \(run.outcome)")
            // Inside, only this pinned failure is a known issue. With
            // `isIntermittent: false`, a test that starts passing records no issue,
            // which `withKnownIssue` reports as a failure of its own.
            withKnownIssue(Comment(rawValue: owner), isIntermittent: false) {
                if run.outcome == .assertionFailed(failure) {
                    Issue.record("\(Self.pinnedFailure): \(entry.path)")
                }
            } matching: { issue in
                issue.comments.contains { $0.rawValue.hasPrefix(Self.pinnedFailure) }
            }
        }
    }

    /// The suite's result, pinned: 32 of 215 pass. A change in any count is red
    /// until the table and this line move together.
    @Test func theSuitesResultIsPinned() {
        var counts: [String: Int] = [:]
        for expectation in LanguageTestExpectation.all.values {
            switch expectation {
            case .pass: counts["pass", default: 0] += 1
            case .expectedFailure: counts["expectedFailure", default: 0] += 1
            case .unsupported: counts["unsupported", default: 0] += 1
            }
        }
        #expect(counts == ["pass": 32, "expectedFailure": 4, "unsupported": 179])
        let pass = counts["pass", default: 0], known = counts["expectedFailure", default: 0]
        let unsupported = counts["unsupported", default: 0]
        print("Catrobat language tests: \(pass)/215 pass, \(known) expected failures, \(unsupported) unsupported")
    }
}
