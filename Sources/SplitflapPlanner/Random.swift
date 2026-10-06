// The planner's randomness, bit for bit the JavaScript planner's: the same seed must pick the same
// letters on every platform, so a board looks the same in React Native, on the web and here.

/// mulberry32: small, fast, good enough for picking letters; returns [0, 1).
final class Rng {
    private var a: UInt32

    init(seed: UInt32) {
        a = seed
    }

    func next() -> Double {
        a = a &+ 0x6d2b_79f5
        var t = a
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

/// Folds integers into one 32-bit seed so (seed, revision, cell) each move every bit. Each part is
/// taken as a 32-bit integer first, as JavaScript's `part | 0` does.
func hash(_ parts: Int...) -> UInt32 {
    var h: UInt32 = 0x811c_9dc5
    for part in parts {
        h ^= UInt32(truncatingIfNeeded: Int32(truncatingIfNeeded: part))
        h = h &* 0x9e37_79b1
        h ^= h >> 15
    }
    return h
}

func pick<T>(_ rng: Rng, _ items: [T]) -> T {
    items[Int((rng.next() * Double(items.count)).rounded(.down))]
}

/// Fisher–Yates permutation of 0..<n.
func permutation(_ rng: Rng, _ n: Int) -> [Int] {
    var order = Array(0..<n)
    var i = n - 1
    while i > 0 {
        let j = Int((rng.next() * Double(i + 1)).rounded(.down))
        order.swapAt(i, j)
        i -= 1
    }
    return order
}

/// JavaScript's Math.round: the nearest integer, halves toward +∞.
func jsRound(_ x: Double) -> Double {
    let down = x.rounded(.down)
    return x - down >= 0.5 ? down + 1 : down
}
