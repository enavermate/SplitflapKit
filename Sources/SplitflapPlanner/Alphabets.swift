// Alphabets are kept by script, never by language. Each script has one canonical order holding every
// letter its languages use — a language's own letters sit next to the letter they grew from (ґ after
// г, ђ after д, ł after l) — and a core shared by nearly all of them. A board travels through the
// core plus whatever extra letters its own old and new text contain.
//
// Anything no table holds — a rare script, a CJK character, a sign — is "other": it changes in one
// step and never rolls, so an unknown alphabet never breaks a board.

enum TableID: Equatable, Sendable {
    case script(SplitflapScript)
    case digit
}

struct Table: Sendable {
    let uid: Int
    let id: TableID
    let order: [String]
    let core: Set<Exact>
    let members: [Exact: Int]

    init(uid: Int, id: TableID, order: [String], core: [String]? = nil) {
        self.uid = uid
        self.id = id
        self.order = order
        self.core = Set((core ?? order).map(Exact.init))
        var members: [Exact: Int] = [:]
        for (i, letter) in order.enumerated() where members[Exact(letter)] == nil {
            members[Exact(letter)] = i
        }
        self.members = members
    }
}

private func letters(_ s: String) -> [String] {
    s.split(separator: " ").map(String.init)
}

private func range(_ from: UInt32, _ to: UInt32) -> [String] {
    (from...to).compactMap { Unicode.Scalar($0).map { String(String.UnicodeScalarView([$0])) } }
}

private func isLetter(_ s: String) -> Bool {
    guard let scalar = s.unicodeScalars.first else { return false }
    switch scalar.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
        return true
    default:
        return false
    }
}

private let blocks: [(SplitflapScript, UInt32, UInt32)] = [
    (.devanagari, 0x0904, 0x0939),
    (.bengali, 0x0985, 0x09b9),
    (.gurmukhi, 0x0a05, 0x0a39),
    (.gujarati, 0x0a85, 0x0ab9),
    (.oriya, 0x0b05, 0x0b39),
    (.tamil, 0x0b85, 0x0bb9),
    (.telugu, 0x0c05, 0x0c39),
    (.kannada, 0x0c85, 0x0cb9),
    (.malayalam, 0x0d05, 0x0d3a),
    (.sinhala, 0x0d85, 0x0dc6),
    (.thai, 0x0e01, 0x0e2e),
    (.lao, 0x0e81, 0x0eae),
    (.tibetan, 0x0f40, 0x0f6c),
    (.myanmar, 0x1000, 0x102a),
    (.khmer, 0x1780, 0x17b3),
    (.hiragana, 0x3041, 0x3096),
    (.katakana, 0x30a1, 0x30fa),
]

private let digitZeros: [UInt32] = [
    0x0030, 0x0660, 0x06f0, 0x0966, 0x09e6, 0x0a66, 0x0ae6, 0x0b66, 0x0be6,
    0x0c66, 0x0ce6, 0x0d66, 0x0de6, 0x0e50, 0x0ed0, 0x0f20, 0x1040, 0x17e0,
    0xff10,
]

struct Alphabets: Sendable {
    let letterTables: [Table]
    let tables: [Table]
    let known: Set<Exact>
    let syllableLetters: Set<Exact>
    let fold: [Exact: String]

    static let shared = Alphabets()

    private init() {
        var uid = 0
        func next() -> Int {
            defer { uid += 1 }
            return uid
        }
        let latin = Table(
            uid: next(), id: .script(.latin),
            order: letters("a æ b c d đ ð e f g h i ı j k l ł m n ñ ŋ o ø œ p q r s ß t þ u v w x y z"),
            core: letters("a b c d e f g h i j k l m n o p q r s t u v w x y z")
        )
        let cyrillic = Table(
            uid: next(), id: .script(.cyrillic),
            order: letters(
                "а ә б в г ґ ғ д ђ ѓ е є ё ж җ з ѕ и і ї й ј к қ ќ л љ м н ң њ о ө п р с т ћ у ў ү ұ ф х һ ц ч џ ш щ ъ ы ь э ю я"
            ),
            core: letters("а б в г д е ж з и к л м н о п р с т у ф х ц ч ш")
        )
        let greek = Table(
            uid: next(), id: .script(.greek),
            order: letters("α β γ δ ε ζ η θ ι κ λ μ ν ξ ο π ρ σ ς τ υ φ χ ψ ω"),
            core: letters("α β γ δ ε ζ η θ ι κ λ μ ν ξ ο π ρ σ τ υ φ χ ψ ω")
        )
        let armenian = Table(
            uid: next(), id: .script(.armenian),
            order: range(0x0561, 0x0586) + ["և"],
            core: range(0x0561, 0x0586)
        )
        let georgian = Table(uid: next(), id: .script(.georgian), order: range(0x10d0, 0x10f0))
        // Unicode encodes these scripts in their traditional order, so each alphabet is its block's
        // letters; the gaps a block keeps for unassigned code points are dropped.
        let syllabic = blocks.map { id, from, to in
            Table(uid: next(), id: .script(id), order: range(from, to).filter(isLetter))
        }
        let digits = digitZeros.map { zero in
            Table(uid: next(), id: .digit, order: range(zero, zero + 9))
        }
        letterTables = [latin, cyrillic, greek, armenian, georgian] + syllabic
        tables = letterTables + digits
        known = Set(tables.flatMap { $0.order.map(Exact.init) })
        syllableLetters = Set(syllabic.flatMap { $0.order.map(Exact.init) })
        var fold: [Exact: String] = [:]
        for (from, to) in zip(foldFrom.codePoints, foldTo.codePoints) where fold[Exact(from)] == nil {
            fold[Exact(from)] = to
        }
        self.fold = fold
    }
}

enum ScriptID: Equatable, Sendable {
    case script(SplitflapScript)
    case digit
    case custom
}

/// The letters a cell of one plan travels through, lowercase, in alphabet order.
struct Script: Sendable {
    /// The table it was cut from; custom alphabets have none.
    let uid: Int
    let id: ScriptID
    let letters: [String]
    let index: [Exact: Int]

    init(uid: Int, id: ScriptID, letters: [String]) {
        self.uid = uid
        self.id = id
        self.letters = letters
        var index: [Exact: Int] = [:]
        for (i, letter) in letters.enumerated() where index[Exact(letter)] == nil {
            index[Exact(letter)] = i
        }
        self.index = index
    }
}

typealias Scripts = [Script]

/// The letter `ch` is filed under: lowercase, an accented letter folded to its base (á → a) unless
/// the accented form is a letter of its own (ñ, й, ё, ї). A glyph no alphabet holds comes back
/// lowercased and is "other".
func base(_ ch: String) -> String {
    let a = Alphabets.shared
    let lower = ch.lowercased()
    if a.known.contains(Exact(lower)) { return lower }
    if let folded = a.fold[Exact(lower)] { return folded }
    let points = lower.codePoints
    if let first = points.first, points.count > 1 {
        // A letter written as its base plus combining marks is filed under the base.
        if points.dropFirst().allSatisfy(isCombiningMark) { return base(first) }
        // A syllable rolls on its first letter; the cell lands on the whole syllable.
        if a.syllableLetters.contains(Exact(first)) { return first }
    }
    return lower
}

private func isCombiningMark(_ ch: String) -> Bool {
    guard let scalar = ch.unicodeScalars.first else { return false }
    if isMark(scalar) { return true }
    let cp = scalar.value
    return (0x0300...0x036f).contains(cp)
        || (0x1ab0...0x1aff).contains(cp)
        || (0x1dc0...0x1dff).contains(cp)
        || (0x20d0...0x20ff).contains(cp)
        || (0xfe20...0xfe2f).contains(cp)
}

private func tableOf(_ ch: String) -> Table? {
    let b = Exact(base(ch))
    return Alphabets.shared.tables.first { $0.members[b] != nil }
}

/// A table cut to its core plus the extra letters `seen` holds.
private func travel(_ t: Table, _ seen: Set<Exact>) -> Script {
    let kept = t.order.filter { t.core.contains(Exact($0)) || seen.contains(Exact($0)) }
    let id: ScriptID
    switch t.id {
    case .script(let s): id = .script(s)
    case .digit: id = .digit
    }
    return Script(uid: t.uid, id: id, letters: kept)
}

/// The alphabets a plan works with. `seen` is every glyph on the board before and after the change:
/// it decides which extra letters each script travels through and, for `auto`, which script the
/// loading words come from (the text's first letter's, else Latin).
func resolveScripts(_ option: AlphabetOption, _ seen: String) -> Scripts {
    if case .letters(let custom) = option {
        var order: [String] = []
        var have = Set<Exact>()
        for point in custom.lowercased().codePoints where have.insert(Exact(point)).inserted {
            order.append(point)
        }
        return [Script(uid: -1, id: .custom, letters: order)]
    }
    let a = Alphabets.shared
    let glyphs = splitGlyphs(seen)
    let bases = Set(glyphs.map { Exact(base($0)) })
    let first: Table?
    switch option {
    case .auto:
        first = glyphs.lazy.compactMap(tableOf).first { $0.id != .digit }
    case .script(let s):
        first = a.letterTables.first { $0.id == .script(s) }
    case .letters:
        first = nil
    }
    let ordered = first.map { f in [f] + a.tables.filter { $0.uid != f.uid } } ?? a.tables
    return ordered.map { travel($0, bases) }
}

/// nil for "" and for anything outside the alphabets ("other").
func scriptOf(_ ch: String, _ scripts: Scripts) -> Script? {
    if ch.isEmpty { return nil }
    let b = Exact(base(ch))
    return scripts.first { $0.index[b] != nil }
}

func indexIn(_ s: Script, _ ch: String) -> Int {
    s.index[Exact(base(ch))] ?? -1
}

func isUpperCase(_ ch: String) -> Bool {
    !ch.isEmpty && !same(ch, ch.lowercased())
}

/// A letter written in the case of `ref`, the glyph the cell is heading to.
func withCase(_ letter: String, _ ref: String) -> String {
    isUpperCase(ref) ? letter.uppercased() : letter
}

/// The letters a scramble cell flickers through before it lands on `target`: its script's letters
/// in the target's case. Empty for a glyph no alphabet holds.
func scrambleLetters(_ target: String, _ scripts: Scripts) -> String {
    guard let s = scriptOf(target, scripts) else { return "" }
    return s.letters.map { withCase($0, target) }.joined()
}

/// `cellWidth` `uniform` and `tiered`: the glyphs a board's cell widths are measured over — every
/// glyph of `text` and the letters each of them travels through, in its case.
public func widthGlyphs(_ text: String) -> String {
    let scripts = resolveScripts(.auto, text)
    var glyphs: [String] = []
    var have = Set<Exact>()
    func add(_ g: String) {
        if have.insert(Exact(g)).inserted { glyphs.append(g) }
    }
    for ch in splitGlyphs(text) {
        add(ch)
        for letter in scrambleLetters(ch, scripts).codePoints { add(letter) }
    }
    // JavaScript's default sort: by UTF-16 code units.
    return glyphs.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }.joined()
}
