#if os(iOS)
import SplitflapPlanner
import UIKit

/// How wide each cell is. Without one, `reel` and `roll` reflow like text, and `flip` and
/// `scramble` keep each letter near its own width — narrow, regular and wide cells measured from the
/// text's alphabets — since they show two glyphs in one cell at once and must not reflow.
public enum SplitflapCellWidth: String, Sendable, CaseIterable {
    /// A cell moves from the old glyph's width to the new one's, as text reflows. `reel` and `roll`
    /// only; `flip` and `scramble` keep their default.
    case natural
    /// Every cell as wide as the alphabet's widest letter, each glyph centred — a station board.
    case uniform
}

/// The modes the view measures in: the public two, and `tiered`, flip's and scramble's default.
enum CellMode: Equatable {
    case natural
    case tiered
    case uniform
}

/// What the view measured for one text: where every glyph sits, as a `UILabel` would place it.
struct Measured: Equatable {
    var cellWidths: [CGFloat] = []
    var lineHeight: CGFloat = 0
    /// `uniform` and `tiered`: the width the atlas centres every glyph in; 0 otherwise.
    var centreWidth: CGFloat = 0

    var total: CGFloat { cellWidths.reduce(0, +) }
}

private struct WidthTier {
    let limit: CGFloat
    let width: CGFloat
}

/// Narrow, regular and wide, read off the alphabet's own widths against its median: any script and
/// font sorts itself, with no list of letters to keep. `single` is `uniform`: one tier, the widest.
private func widthTiers(_ alphabet: [CGFloat], single: Bool) -> [WidthTier] {
    guard !alphabet.isEmpty else { return [] }
    let sorted = alphabet.sorted()
    if single { return [WidthTier(limit: .infinity, width: ceil(sorted.last!))] }
    let median = sorted[sorted.count / 2]
    let narrowLimit = median * 0.75
    let wideLimit = median * 1.25
    var narrow: CGFloat = 0, regular: CGFloat = 0, wide: CGFloat = 0
    for width in sorted {
        if width <= narrowLimit {
            narrow = max(narrow, width)
        } else if width < wideLimit {
            regular = max(regular, width)
        } else {
            wide = max(wide, width)
        }
    }
    var tiers: [WidthTier] = []
    if narrow > 0 { tiers.append(WidthTier(limit: narrowLimit, width: ceil(narrow))) }
    if regular > 0 { tiers.append(WidthTier(limit: wideLimit, width: ceil(regular))) }
    if wide > 0 { tiers.append(WidthTier(limit: .infinity, width: ceil(wide))) }
    return tiers
}

/// A glyph outside the alphabets still never gets a cell narrower than itself.
private func tierWidth(_ tiers: [WidthTier], _ width: CGFloat) -> CGFloat {
    for tier in tiers where width <= tier.limit { return max(tier.width, ceil(width)) }
    return ceil(width)
}

@MainActor
enum Measure {
    // The alphabets of one font are the same for every board that shows them, and measuring
    // thirty-odd glyphs on every text change is what keeps sixty boards from holding their frame
    // rate. Measured once per alphabet set, font and spacing.
    private static var alphabetWidths: [String: [CGFloat]] = [:]
    private static let alphabetCacheLimit = 256

    static func width(_ glyph: String, _ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        glyph.isEmpty ? 0 : (glyph as NSString).size(withAttributes: attributes).width
    }

    static func measure(
        glyphs: [String], text: String, mode: CellMode,
        font: UIFont, letterSpacing: CGFloat, lineHeight: CGFloat?
    ) -> Measured {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: letterSpacing]
        var measured = Measured()
        // A reference glyph keeps the line height stable across texts and defined for an empty one.
        measured.lineHeight = lineHeight ?? ceil(("H" as NSString).size(withAttributes: attributes).height)
        let own = glyphs.map { width($0, attributes) }
        switch mode {
        case .natural:
            measured.cellWidths = own
        case .tiered, .uniform:
            let alphabetGlyphs = widthGlyphs(text)
            let key = "\(alphabetGlyphs)\u{0}\(font.fontName)\u{0}\(font.pointSize)\u{0}\(font.fontDescriptor.fontAttributes.description.hashValue)\u{0}\(letterSpacing)"
            var alphabet = alphabetWidths[key] ?? []
            if alphabet.isEmpty {
                alphabet = splitGlyphs(alphabetGlyphs).map { width($0, attributes) }
                if alphabetWidths.count >= alphabetCacheLimit { alphabetWidths.removeAll() }
                alphabetWidths[key] = alphabet
            }
            // The text's own glyphs count too: one outside every alphabet must still fit.
            if mode == .uniform { alphabet += own }
            let tiers = widthTiers(alphabet, single: mode == .uniform)
            measured.cellWidths = own.map { tierWidth(tiers, $0) }
            measured.centreWidth = max(
                tiers.map(\.width).max() ?? 0,
                measured.cellWidths.max() ?? 0
            )
        }
        return measured
    }

    /// How many glyphs fit before a trailing "…" in `available` points, or nil when all of them fit.
    /// Trailing spaces before the "…" are dropped, as UIKit's one-line truncation does.
    static func visibleCount(
        _ measured: Measured, glyphs: [String], available: CGFloat,
        font: UIFont, letterSpacing: CGFloat
    ) -> Int? {
        guard available > 0, measured.total > available + 0.5 else { return nil }
        let ellipsis = width("…", [.font: font, .kern: letterSpacing])
        var fit = 0
        var used: CGFloat = 0
        while fit < measured.cellWidths.count, used + measured.cellWidths[fit] + ellipsis <= available + 0.5 {
            used += measured.cellWidths[fit]
            fit += 1
        }
        while fit > 0, fit - 1 < glyphs.count, glyphs[fit - 1] == " " { fit -= 1 }
        return fit < glyphs.count ? fit : nil
    }
}
#endif
