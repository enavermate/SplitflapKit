/// Milliseconds one cell takes; `flip` takes 1.6 times this.
public let defaultDurationMs: Double = 650
/// Milliseconds between the starts of consecutive changed cells.
public let defaultStaggerMs: Double = 40

/// Cell index reserved for board-level randomness (the random stagger order).
private let boardCell = -1
/// Cell index reserved for the board's coin: which parity of cells comes from above.
private let boardDirection = -2

/// An empty board for the planner.
public func createBoard() -> Board {
    Board(revision: 0, cells: [])
}

private struct Draft {
    var i: Int
    var to: String
    var from: String
    var resume: Resume?
}

private func drafts(_ board: Board, _ text: String, _ now: Double) -> [Draft] {
    let chars = splitGlyphs(text)
    let n = max(chars.count, board.cells.count)
    return (0..<n).map { i in
        let origin = originAt(i < board.cells.count ? board.cells[i] : nil, now)
        return Draft(i: i, to: i < chars.count ? chars[i] : "", from: origin.from, resume: origin.resume)
    }
}

private func settled(_ d: Draft) -> CellPlan {
    CellPlan(
        i: d.i, from: d.to, to: d.to, path: [d.to], delayMs: 0, durationMs: 0,
        easing: .out, dir: 1, stepMs: nil, letters: nil, land: 0, resume: d.resume
    )
}

private func staggerOrdinals(_ count: Int, _ order: StaggerOrder, _ seed: UInt32) -> [Int] {
    switch order {
    case .ltr: return Array(0..<count)
    case .rtl: return (0..<count).map { count - 1 - $0 }
    case .random: return permutation(Rng(seed: seed), count)
    }
}

private struct Settings {
    var transition: SplitflapTransition
    var duration: Double
    var stagger: Double
    var direction: Direction
    /// `random`: the parity of the cells that come from above on this change.
    var topParity: Int
    var seed: Int
    var revision: Int
    var scripts: Scripts
}

private func forcedDir(_ s: Settings, _ i: Int, _ dir: Int) -> Int {
    switch s.direction {
    case .up: return 1
    case .down: return -1
    // -1: the new glyph comes from above.
    case .random: return i % 2 == s.topParity ? -1 : 1
    case .auto: return dir
    }
}

private func animated(_ d: Draft, _ ordinal: Int, _ s: Settings) -> CellPlan {
    let rng = Rng(seed: hash(s.seed, s.revision, d.i))
    let cp = cellPath(s.transition, d.from, d.to, PathContext(scripts: s.scripts, rng: rng))
    var cell = CellPlan(
        i: d.i, from: d.from, to: d.to, path: cp.path,
        delayMs: Double(ordinal) * s.stagger,
        durationMs: durationFor(s.transition, s.duration),
        easing: d.resume != nil ? .out : easingFor(s.transition),
        dir: forcedDir(s, d.i, cp.dir),
        stepMs: nil, letters: nil,
        land: cp.path.count - 1,
        resume: d.resume
    )
    if s.transition == .scramble {
        cell.stepMs = scrambleStepMs
        if !d.to.isEmpty { cell.letters = scrambleLetters(d.to, s.scripts) }
    }
    return cell
}

/// Trailing cells that are empty on both sides carry nothing for the player; the board forgets them.
private func withoutTrailingBlanks(_ cells: [CellPlan]) -> [CellPlan] {
    var end = cells.count
    while end > 0, cells[end - 1].from.isEmpty, cells[end - 1].to.isEmpty { end -= 1 }
    return Array(cells[..<end])
}

private func totalMs(_ cells: [CellPlan]) -> Double {
    cells.reduce(0) { max($0, $1.delayMs + $1.durationMs) }
}

/// Plans a change of text: every cell's path, timing and direction. Retargets from wherever the
/// cells are at `input.now`.
public func planTransition(_ board: Board, _ input: TransitionInput) -> (plan: Plan, board: Board) {
    let transition = input.transition ?? .reel
    let revision = board.revision + 1
    let seed = input.seed ?? 1
    let all = drafts(board, input.text, input.now)

    var cells: [CellPlan]
    if input.instant {
        cells = all.map { settled(Draft(i: $0.i, to: $0.to, from: $0.to, resume: nil)) }
    } else {
        let settings = Settings(
            transition: transition,
            duration: input.duration ?? defaultDurationMs,
            stagger: input.stagger ?? defaultStaggerMs,
            direction: input.direction ?? .random,
            topParity: Rng(seed: hash(seed, revision, boardDirection)).next() < 0.5 ? 0 : 1,
            seed: seed,
            revision: revision,
            // Every glyph before and after: a letter the board is leaving must still be in its alphabet.
            scripts: resolveScripts(input.alphabet ?? .auto, all.map { $0.from + $0.to }.joined())
        )
        let changed = all.filter { !same($0.from, $0.to) }
        let ordinals = staggerOrdinals(
            changed.count, input.staggerOrder ?? .ltr, hash(seed, revision, boardCell)
        )
        var ordinalOf: [Int: Int] = [:]
        for (n, d) in changed.enumerated() { ordinalOf[d.i] = ordinals[n] }
        cells = all.map { d in
            if let ordinal = ordinalOf[d.i] { return animated(d, ordinal, settings) }
            return settled(d)
        }
    }
    cells = withoutTrailingBlanks(cells)

    let plan = Plan(transition: transition, totalMs: totalMs(cells), cells: cells, loop: nil)
    let next = Board(revision: revision, cells: cells.map { BoardCell(cell: $0, startMs: input.now, loopMs: nil) })
    return (plan, next)
}
