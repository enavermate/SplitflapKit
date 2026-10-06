// Swift compares strings by canonical equivalence ("é" equals "e" + U+0301); the planner compares
// code points, as JavaScript does, so a cell from one to the other is a change on every platform.

/// A string compared and hashed by its exact code points.
struct Exact: Hashable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    static func == (a: Exact, b: Exact) -> Bool {
        a.value.unicodeScalars.elementsEqual(b.value.unicodeScalars)
    }

    func hash(into hasher: inout Hasher) {
        for scalar in value.unicodeScalars {
            hasher.combine(scalar.value)
        }
    }
}

func same(_ a: String, _ b: String) -> Bool {
    a.unicodeScalars.elementsEqual(b.unicodeScalars)
}

extension String {
    /// The string's code points, each as a string of its own — JavaScript's `Array.from(text)`.
    var codePoints: [String] {
        unicodeScalars.map { String(String.UnicodeScalarView([$0])) }
    }
}
