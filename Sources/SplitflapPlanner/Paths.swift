struct CellPath {
    var path: [String]
    var dir: Int
}

struct PathContext {
    let scripts: Scripts
    let rng: Rng
}

private let neighbourReach = 9

private func randomLetters(_ n: Int, _ s: Script, _ caseRef: String, _ rng: Rng) -> [String] {
    (0..<n).map { _ in withCase(pick(rng, s.letters), caseRef) }
}

private func oneStep(_ from: String, _ to: String, _ dir: Int = 1) -> CellPath {
    CellPath(path: [from, to], dir: dir)
}

private func through(_ from: String, _ letters: [String], _ to: String, _ dir: Int = 1) -> CellPath {
    CellPath(path: [from] + letters + [to], dir: dir)
}

/// Same script, target later in the alphabet → 1; different scripts read as forward.
private func orderDir(_ from: String, _ to: String, _ scripts: Scripts) -> Int {
    guard let sf = scriptOf(from, scripts), let st = scriptOf(to, scripts), sf.uid == st.uid else {
        return 1
    }
    return indexIn(sf, to) >= indexIn(sf, from) ? 1 : -1
}

/// A cell that appears or disappears rolls through a few letters, so a word grows or shrinks during
/// the roll, not after it.
private func edgePath(_ from: String, _ to: String, _ steps: Int, _ ctx: PathContext) -> CellPath {
    guard let s = scriptOf(from.isEmpty ? to : from, ctx.scripts) else { return oneStep(from, to) }
    return through(from, randomLetters(steps, s, to.isEmpty ? from : to, ctx.rng), to)
}

private func rollPath(_ from: String, _ to: String, _ ctx: PathContext) -> CellPath {
    if from.isEmpty || to.isEmpty { return edgePath(from, to, 2, ctx) }
    return oneStep(from, to, orderDir(from, to, ctx.scripts))
}

private func alphabetPath(_ from: String, _ to: String, _ ctx: PathContext, flip: Bool) -> CellPath {
    if to.isEmpty && flip { return oneStep(from, "", -1) }
    if from.isEmpty || to.isEmpty { return edgePath(from, to, 3, ctx) }
    let sf = scriptOf(from, ctx.scripts)
    let st = scriptOf(to, ctx.scripts)
    if let sf, let st, sf.uid == st.uid {
        let i = indexIn(sf, from)
        let j = indexIn(sf, to)
        let step = j > i ? 1 : -1
        let dist = abs(j - i)
        if dist == 0 { return oneStep(from, to) }
        if dist <= neighbourReach {
            var between: [String] = []
            var k = i + step
            while k != j {
                between.append(withCase(sf.letters[k], to))
                k += step
            }
            return through(from, between, to, step)
        }
        return through(from, randomLetters(5, sf, to, ctx.rng), to, step)
    }
    guard let st else { return oneStep(from, to) }
    return through(from, randomLetters(3, st, to, ctx.rng), to)
}

func cellPath(_ transition: SplitflapTransition, _ from: String, _ to: String, _ ctx: PathContext) -> CellPath {
    switch transition {
    case .roll: return rollPath(from, to, ctx)
    case .scramble: return oneStep(from, to, orderDir(from, to, ctx.scripts))
    case .reel: return alphabetPath(from, to, ctx, flip: false)
    case .flip: return alphabetPath(from, to, ctx, flip: true)
    }
}

func durationFor(_ transition: SplitflapTransition, _ duration: Double) -> Double {
    transition == .flip ? jsRound(duration * 1.6) : duration
}

func easingFor(_ transition: SplitflapTransition) -> Easing {
    switch transition {
    case .reel: return .inOut
    case .flip: return .linear
    default: return .out
    }
}

let scrambleStepMs: Double = 55
