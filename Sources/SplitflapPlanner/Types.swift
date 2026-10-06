/// How every changed cell moves.
public enum SplitflapTransition: String, Codable, Sendable, CaseIterable {
    /// Flips over in halves, like a departure board.
    case flip
    /// Spins through the alphabet between the old letter and the new one.
    case reel
    /// Rolls through a few letters: its neighbours when the new one is close, random ones when far.
    case roll
    /// Flickers through random letters of its own script, then locks.
    case scramble
}

/// The curve a cell's travel follows.
public enum Easing: String, Codable, Sendable {
    case out
    case inOut
    case linear
}

/// The order the changed cells start in.
public enum StaggerOrder: String, Codable, Sendable, CaseIterable {
    case ltr
    case rtl
    case random
}

/// Which way `reel` and `roll` cells travel.
public enum Direction: String, Codable, Sendable, CaseIterable {
    /// Every other cell comes from above and the rest from below, picked anew on each change.
    case random
    /// Each cell rolls the way its letter lies in the alphabet.
    case auto
    case up
    case down
}

/// The scripts the board has an alphabet for.
public enum SplitflapScript: String, Codable, Sendable, CaseIterable {
    case latin, cyrillic, greek, armenian, georgian
    case devanagari, bengali, gurmukhi, gujarati, oriya, tamil, telugu, kannada, malayalam, sinhala
    case thai, lao, tibetan, myanmar, khmer
    case hiragana, katakana
}

/// The letters a cell travels through.
public enum AlphabetOption: Equatable, Sendable {
    /// Each letter's own script, read from the text.
    case auto
    /// The same, and the loading words are written in this script.
    case script(SplitflapScript)
    /// Only these letters, in this order.
    case letters(String)
}

/// Where an interrupted cell was: between `path[k]` and `path[k + 1]`, `f` of the way.
public struct Resume: Codable, Equatable, Sendable {
    public var k: Int
    public var f: Double
}

/// One cell's part of a change: its path, timing and direction.
public struct CellPlan: Codable, Equatable, Sendable {
    public var i: Int
    public var from: String
    public var to: String
    public var path: [String]
    public var delayMs: Double
    public var durationMs: Double
    public var easing: Easing
    /// 1: the new glyph comes from below; -1: from above.
    public var dir: Int
    public var stepMs: Double?
    public var letters: String?
    public var land: Int
    public var resume: Resume?
}

/// One change of the whole board.
public struct Plan: Codable, Equatable, Sendable {
    public var v: Int = 1
    public var transition: SplitflapTransition
    public var totalMs: Double
    public var cells: [CellPlan]
    public var loop: Bool?
}

/// What the planner remembers between changes.
public struct BoardCell: Codable, Equatable, Sendable {
    public var cell: CellPlan
    public var startMs: Double
    public var loopMs: Double?

    public init(cell: CellPlan, startMs: Double, loopMs: Double? = nil) {
        self.cell = cell
        self.startMs = startMs
        self.loopMs = loopMs
    }
}

/// The planner's memory of a board. Immutable: every call returns a new one.
public struct Board: Codable, Equatable, Sendable {
    public var revision: Int
    public var cells: [BoardCell]

    public init(revision: Int = 0, cells: [BoardCell] = []) {
        self.revision = revision
        self.cells = cells
    }
}

/// A change of text to plan.
public struct TransitionInput: Sendable {
    public var text: String
    public var transition: SplitflapTransition?
    public var duration: Double?
    public var stagger: Double?
    public var staggerOrder: StaggerOrder?
    public var direction: Direction?
    public var alphabet: AlphabetOption?
    public var seed: Int?
    /// The plan's start on your clock — the same clock for later retargets.
    public var now: Double
    /// Settles every cell at once.
    public var instant: Bool

    public init(
        text: String,
        now: Double,
        transition: SplitflapTransition? = nil,
        duration: Double? = nil,
        stagger: Double? = nil,
        staggerOrder: StaggerOrder? = nil,
        direction: Direction? = nil,
        alphabet: AlphabetOption? = nil,
        seed: Int? = nil,
        instant: Bool = false
    ) {
        self.text = text
        self.now = now
        self.transition = transition
        self.duration = duration
        self.stagger = stagger
        self.staggerOrder = staggerOrder
        self.direction = direction
        self.alphabet = alphabet
        self.seed = seed
        self.instant = instant
    }
}
