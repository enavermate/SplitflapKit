/// How long each loading word shows, in milliseconds.
public let loadingWordMs: Double = 430
/// How many words one loading loop holds.
public let loadingWords = 8

/// Cell index reserved for word generation; real cells are 0-based.
private let wordsCell = -2

/// How long the loading words are: a number of cells, or a range the lengths are drawn from — the
/// shortest and the longest text the board is waiting for.
public enum LoadingLength: Equatable, Sendable {
    case cells(Int)
    case range(min: Double, max: Double)
}

public struct LoadingOptions: Sendable {
    public var now: Double
    public var alphabet: AlphabetOption?
    /// The text the board will land on, if known: with `auto`, the loading words take its script.
    public var text: String?
    public var wordMs: Double?
    /// How the words change while loading; the one the real text will land with, so they match.
    public var transition: SplitflapTransition?
    /// A `cells` length: every word exactly that many cells instead of wandering ±1 around it.
    public var exactLength: Bool

    public init(
        now: Double,
        alphabet: AlphabetOption? = nil,
        text: String? = nil,
        wordMs: Double? = nil,
        transition: SplitflapTransition? = nil,
        exactLength: Bool = false
    ) {
        self.now = now
        self.alphabet = alphabet
        self.text = text
        self.wordMs = wordMs
        self.transition = transition
        self.exactLength = exactLength
    }
}

private func randomWord(_ length: Int, _ s: Script, _ previous: [String], _ rng: Rng) -> [String] {
    (0..<max(0, length)).map { i in
        let letter = pick(rng, s.letters)
        // A cell that would keep its letter looks stuck; one reroll breaks most repeats.
        return i < previous.count && same(letter, previous[i]) ? pick(rng, s.letters) : letter
    }
}

private func lengthRange(_ length: LoadingLength, _ exact: Bool) -> (min: Double, max: Double) {
    switch length {
    case .cells(let n):
        return exact ? (Double(n), Double(n)) : (Double(n - 1), Double(n + 1))
    case .range(let lo, let hi):
        // An app's numbers: whole cells, at least one, in either order.
        let a = lo.rounded(.down)
        let b = hi.rounded(.down)
        return (Swift.min(a, b), Swift.max(a, b))
    }
}

private func randomWords(_ length: LoadingLength, _ s: Script, _ rng: Rng, _ exact: Bool) -> [[String]] {
    let range = lengthRange(length, exact)
    let lo = Swift.max(1, range.min.isFinite ? range.min : 1)
    let hi = Swift.max(lo, range.max.isFinite ? range.max : lo)
    var words: [[String]] = []
    for w in 0..<loadingWords {
        let len = lo + (rng.next() * (hi - lo + 1)).rounded(.down)
        words.append(randomWord(Int(len), s, w > 0 ? words[w - 1] : [], rng))
    }
    return words
}

/// The script the loading words are written in. `auto` takes the text's letters; a text with none —
/// a count, a price, a time — takes its digits. A named or custom alphabet is used as given.
private func wordScript(_ scripts: Scripts, _ alphabet: AlphabetOption?, _ glyphs: [String]) -> Script {
    if alphabet == nil || alphabet == .auto {
        let seen = glyphs.map { scriptOf($0, scripts) }
        if let found = seen.lazy.compactMap({ $0 }).first(where: { $0.id != .digit })
            ?? seen.lazy.compactMap({ $0 }).first
        {
            return found
        }
    }
    return scripts[0]
}

/// A looping plan that shows a new random word every `wordMs`. Every cell steps exactly once per
/// word, on a linear clock, so `planTransition` on the returned board lands from whatever word is
/// on screen.
public func loadingPlan(_ length: LoadingLength, seed: Int, options: LoadingOptions) -> (plan: Plan, board: Board) {
    let wordMs = options.wordMs ?? loadingWordMs
    let scripts = resolveScripts(options.alphabet ?? .auto, options.text ?? "")
    let glyphs = splitGlyphs(options.text ?? "")
    // A board written in capitals — a station board — loads in capitals too.
    let letters = glyphs.filter { !same($0.lowercased(), $0.uppercased()) }
    let capitals = !letters.isEmpty && letters.allSatisfy(isUpperCase)
    let words = randomWords(
        length,
        wordScript(scripts, options.alphabet, glyphs),
        Rng(seed: hash(seed, 0, wordsCell)),
        options.exactLength
    ).map { word in capitals ? word.map { $0.uppercased() } : word }
    let cycle = words + [words[0]]
    let width = words.map(\.count).max() ?? 0
    let durationMs = Double(loadingWords) * wordMs

    let cells: [CellPlan] = (0..<width).map { i in
        let path = cycle.map { i < $0.count ? $0[i] : "" }
        let to = path[loadingWords]
        return CellPlan(
            i: i, from: path[0], to: to, path: path, delayMs: 0, durationMs: durationMs,
            easing: .linear, dir: 1, stepMs: nil,
            letters: options.transition == .scramble && !to.isEmpty ? scrambleLetters(to, scripts) : nil,
            land: loadingWords, resume: nil
        )
    }
    let plan = Plan(transition: options.transition ?? .reel, totalMs: durationMs, cells: cells, loop: true)
    let board = Board(
        revision: 0,
        cells: cells.map { BoardCell(cell: $0, startMs: options.now, loopMs: durationMs) }
    )
    return (plan, board)
}
