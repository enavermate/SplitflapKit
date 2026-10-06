/// What one cell shows: a user-perceived character, not a code point. A flag, a family emoji, a
/// keycap, an "é" written as "e" plus a combining accent — each is one cell, never torn apart.
///
/// A syllable of an Indic or Thai script is one cell too: a consonant with its vowel signs, and
/// consonants joined by a virama (Unicode's conjunct rule GB9c).
///
/// This is the same deliberate subset of Unicode's extended grapheme clusters the JavaScript
/// planner uses — not Swift's `Character` — so a text splits into the same cells on every platform.
public func splitGlyphs(_ text: String) -> [String] {
    var out: [String.UnicodeScalarView] = []
    var joinNext = false
    var flagHalf = false
    var linker: UInt32? = nil
    for scalar in text.unicodeScalars {
        let cp = scalar.value
        let conjunct = linker.map { sameBlock($0, cp) && !isMark(scalar) } ?? false
        if !out.isEmpty
            && (joinNext || conjunct || extendsPrevious(scalar) || (flagHalf && isRegionalIndicator(cp)))
        {
            out[out.count - 1].append(scalar)
            joinNext = cp == zwj
            flagHalf = false
            linker = linkers.contains(cp) ? cp : cp == zwj ? linker : nil
            continue
        }
        out.append(String.UnicodeScalarView([scalar]))
        joinNext = false
        flagHalf = isRegionalIndicator(cp)
        linker = nil
    }
    return out.map(String.init)
}

private let zwj: UInt32 = 0x200d

/// The viramas that join the consonant after them into one conjunct (Unicode InCB=Linker).
private let linkers: Set<UInt32> = [0x094d, 0x09cd, 0x0acd, 0x0b4d, 0x0c4d, 0x0d4d]

/// A linker joins only a consonant of its own script, and each Indic script has its own block.
private func sameBlock(_ a: UInt32, _ b: UInt32) -> Bool {
    a / 128 == b / 128
}

func isMark(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .nonspacingMark, .spacingMark, .enclosingMark: return true
    default: return false
    }
}

private func isRegionalIndicator(_ cp: UInt32) -> Bool {
    cp >= 0x1f1e6 && cp <= 0x1f1ff
}

/// A code point that belongs to the character before it.
private func extendsPrevious(_ scalar: Unicode.Scalar) -> Bool {
    let cp = scalar.value
    return cp == zwj
        || isMark(scalar)
        || (0x0300...0x036f).contains(cp)
        || (0x1ab0...0x1aff).contains(cp)
        || (0x1dc0...0x1dff).contains(cp)
        || (0x20d0...0x20ff).contains(cp)
        || (0xfe00...0xfe0f).contains(cp)
        || (0xfe20...0xfe2f).contains(cp)
        || (0x1f3fb...0x1f3ff).contains(cp)
        || (0xe0020...0xe007f).contains(cp)
        || (0xe0100...0xe01ef).contains(cp)
}
