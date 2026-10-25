public extension DesignName {
    /// This name made unique among `taken` as `"<base> N"`, still a valid `LA` name (Project
    /// management, brief D4). For names the app generates — a duplicate's, a new draft's, a
    /// sample opened as a project — never for a name the user typed.
    ///
    /// - The name itself if it is free.
    /// - Otherwise an existing suffix (a terminal ASCII space and decimal integer) is stripped,
    ///   and N counts up from 2, so a duplicate of "Flower 2" is "Flower 3", not "Flower 2 2".
    /// - The base is cut to leave room for the suffix inside the 15-character field, and any
    ///   spaces the cut leaves at its end are removed: "Octagon Rosette" becomes
    ///   "Octagon Roset 2".
    /// - Names compare as the field stores them (trimmed), folding ASCII case only. A taken
    ///   name may hold anything — one read from a refused file need not be valid — and only
    ///   ASCII letters can collide with a valid name.
    func uniqued(avoiding taken: some Collection<String>) -> DesignName {
        let occupied = Set(taken.map { Self.folded(Self.normalised($0)) })
        guard occupied.contains(Self.folded(value)) else { return self }
        let base = Self.strippingNumber(value)
        var number = 2
        while true {
            let suffix = " \(number)"
            var stem = String(base.prefix(Self.maximumLength - suffix.count))
            while stem.last == " " {
                stem.removeLast()
            }
            let candidate = stem + suffix
            if !occupied.contains(Self.folded(candidate)) {
                // Valid by construction: a printable-ASCII stem, a space and digits, within the
                // field. A failure here is a bug in this function, so it stops rather than
                // looping past it (found by mutation: a 16-character cut never returned).
                guard case let .success(name) = Self.validating(candidate) else {
                    preconditionFailure("generated design name \(candidate) is not valid")
                }
                return name
            }
            number += 1
        }
    }

    /// `value` without a terminal " N", if it has one with a word before it.
    private static func strippingNumber(_ value: String) -> String {
        guard let space = value.lastIndex(of: " ") else { return value }
        let digits = value[value.index(after: space)...]
        guard !digits.isEmpty, digits.allSatisfy({ ("0" ... "9").contains($0) }) else { return value }
        let stem = value[..<space].trimmingCharacters(in: .whitespaces)
        return stem.isEmpty ? value : stem
    }

    /// ASCII-only case folding: `A`–`Z` to `a`–`z`, everything else unchanged.
    private static func folded(_ name: String) -> String {
        String(name.unicodeScalars.map { scalar in
            ("A" ... "Z").contains(scalar) ? Character(Unicode.Scalar(scalar.value + 32)!) : Character(scalar)
        })
    }
}
