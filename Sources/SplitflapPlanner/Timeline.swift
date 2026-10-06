import Foundation

/// The curves every player uses; a retarget lands on the wrong glyph if they differ.
public func ease(_ easing: Easing, _ t: Double) -> Double {
    switch easing {
    case .out: return 1 - pow(1 - t, 3)
    case .inOut: return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    case .linear: return t
    }
}

/// The inverse of `ease`: the time at which a cell has travelled `y` of the way.
public func easeInverse(_ easing: Easing, _ y: Double) -> Double {
    switch easing {
    case .out: return 1 - cbrt(1 - y)
    case .inOut: return y < 0.5 ? cbrt(y / 4) : 1 - cbrt(2 - 2 * y) / 2
    case .linear: return y
    }
}

public struct Position: Equatable, Sendable {
    /// Pair (path[k], path[k + 1]) currently on screen.
    public var k: Int
    /// Fraction travelled from path[k] to path[k + 1].
    public var f: Double
    public var moving: Bool
}

private func cellTime(_ bc: BoardCell, _ now: Double) -> Double {
    var t = now - bc.startMs
    if let loop = bc.loopMs, loop > 0 {
        t = (t.truncatingRemainder(dividingBy: loop) + loop).truncatingRemainder(dividingBy: loop)
    }
    return t - bc.cell.delayMs
}

public func positionAt(_ bc: BoardCell, _ now: Double) -> Position {
    let cell = bc.cell
    let t = cellTime(bc, now)
    if cell.land <= 0 || cell.durationMs <= 0 || t >= cell.durationMs {
        return Position(k: cell.land, f: 0, moving: false)
    }
    if t <= 0 { return Position(k: 0, f: 0, moving: false) }
    let p = ease(cell.easing, t / cell.durationMs) * Double(cell.land)
    let k = Int(p.rounded(.down))
    if k >= cell.land { return Position(k: cell.land, f: 0, moving: false) }
    return Position(k: k, f: p - Double(k), moving: true)
}

/// The glyph a viewer sees most of at `now`.
public func glyphAt(_ bc: BoardCell, _ now: Double) -> String {
    let pos = positionAt(bc, now)
    let path = bc.cell.path
    let index = pos.f < 0.5 ? pos.k : min(pos.k + 1, path.count - 1)
    return path.indices.contains(index) ? path[index] : ""
}

struct Origin {
    var from: String
    var resume: Resume?
}

/// Where a new plan for this cell starts: the glyph on screen, plus the pair and fraction to
/// continue from if it is moving.
func originAt(_ bc: BoardCell?, _ now: Double) -> Origin {
    guard let bc else { return Origin(from: "") }
    let from = glyphAt(bc, now)
    let pos = positionAt(bc, now)
    return pos.moving
        ? Origin(from: from, resume: Resume(k: pos.k, f: jsRound(pos.f * 1000) / 1000))
        : Origin(from: from)
}
