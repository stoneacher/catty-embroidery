import Testing

/// The generator's literals must be Swift source for every value a failure can carry.
struct RegenerateExpectationsTests {
    @Test(arguments: [
        (Double.nan, ".nan"), (.infinity, ".infinity"), (-.infinity, "-.infinity"),
        (1.2000000000000002, "1.2000000000000002"), (-0.0, "-0.0"), (60, "60.0")
    ])
    func doubleLiteralsAreSwiftSource(value: Double, source: String) {
        #expect(RegenerateExpectations.literal(value) == source)
    }
}
