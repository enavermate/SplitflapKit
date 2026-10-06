#if os(iOS)
import UIKit

/// Every glyph a board can show, rasterised once into one image; a cell shows a glyph through
/// `contentsRect`, so a transition never draws text. Tiles share one width (the widest glyph) so a
/// layer's bounds never change while its `contentsRect` steps through a path.
///
/// `centreWidth` > 0 (`uniform` and `tiered` boards): each glyph is drawn centred in that width.
/// Atlases are cached per font, colour, spacing, line height, scale and centre width under an 8 MB
/// budget, and dropped on a memory warning.
@MainActor
final class GlyphAtlas {
    let image: CGImage
    let scale: CGFloat
    /// Tile height, in points: the line height every cell is laid out on.
    let tileHeight: CGFloat
    /// Tile width, in points, padding included.
    let tileWidth: CGFloat
    /// Transparent space left of every glyph, so overhangs (italics) are not cut.
    let padding: CGFloat

    private let key: String
    private let glyphs: Set<String>
    private let bytes: Int
    private let rects: [String: CGRect]
    private let advances: [String: CGFloat]
    private let glyphsByRect: [(CGRect, String)]

    private static let budgetBytes = 8 * 1024 * 1024
    private static let maxRowWidth: CGFloat = 2048
    private static var cache: [String: GlyphAtlas] = [:]
    private static var order: [String] = []
    private static var observing = false

    static func clearCache() {
        cache.removeAll()
        order.removeAll()
    }

    static func atlas(
        font: UIFont, color: UIColor, letterSpacing: CGFloat, lineHeight: CGFloat,
        scale: CGFloat, centreWidth: CGFloat, glyphs: Set<String>
    ) -> GlyphAtlas {
        if !observing {
            observing = true
            NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { GlyphAtlas.clearCache() }
            }
        }
        // The descriptor's attributes carry the font features (tabular digits): the same font name
        // with and without them draws different advances, so they belong in the key.
        let key = [
            font.fontName,
            String(font.fontDescriptor.fontAttributes.description.hashValue),
            String(format: "%.2f", font.pointSize),
            colorKey(color),
            String(format: "%.2f|%.2f|%.1f|%.2f", letterSpacing, lineHeight, scale, centreWidth),
        ].joined(separator: "|")
        var wanted = glyphs
        wanted.insert("")
        if let cached = cache[key] {
            touch(key)
            if wanted.isSubset(of: cached.glyphs) { return cached }
            wanted.formUnion(cached.glyphs)
        }
        let atlas = GlyphAtlas(
            font: font, color: color, letterSpacing: letterSpacing, lineHeight: lineHeight,
            scale: scale, centreWidth: centreWidth, glyphs: wanted, key: key
        )
        cache[key] = atlas
        touch(key)
        evictToBudget()
        return atlas
    }

    private static func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private static func evictToBudget() {
        var total = cache.values.reduce(0) { $0 + $1.bytes }
        while total > budgetBytes, order.count > 1 {
            let oldest = order.removeFirst()
            total -= cache[oldest]?.bytes ?? 0
            cache[oldest] = nil
        }
    }

    private static func colorKey(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.3f,%.3f,%.3f,%.3f", r, g, b, a)
    }

    private init(
        font: UIFont, color: UIColor, letterSpacing: CGFloat, lineHeight: CGFloat,
        scale: CGFloat, centreWidth: CGFloat, glyphs: Set<String>, key: String
    ) {
        self.key = key
        self.scale = scale
        self.glyphs = glyphs
        padding = ceil(font.pointSize * 0.25)
        tileHeight = lineHeight > 0 ? lineHeight : ceil(font.lineHeight)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: letterSpacing]

        let ordered = glyphs.sorted()
        var advances: [String: CGFloat] = [:]
        var widest: CGFloat = 0
        for glyph in ordered {
            let advance = glyph.isEmpty ? 0 : (glyph as NSString).size(withAttributes: attributes).width
            advances[glyph] = advance
            widest = max(widest, advance)
        }
        // A centred board draws every glyph in the middle of the cell width, so the layers need no
        // offset of their own.
        let content = max(widest, centreWidth)
        let tileWidth = ceil(content) + 2 * padding
        self.tileWidth = tileWidth

        let perRow = max(1, Int(floor(Self.maxRowWidth / tileWidth)))
        let rows = (ordered.count + perRow - 1) / perRow
        let imageSize = CGSize(width: tileWidth * CGFloat(min(perRow, ordered.count)), height: tileHeight * CGFloat(rows))
        // A glyph sits in the middle of a line height taller than the font.
        let topOffset = tileHeight > font.lineHeight ? (tileHeight - font.lineHeight) / 2 : 0

        var rects: [String: CGRect] = [:]
        var glyphsByRect: [(CGRect, String)] = []
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = scale
        format.opaque = false
        let padding = self.padding
        let tileHeight = self.tileHeight
        let rendered = UIGraphicsImageRenderer(size: imageSize, format: format).image { _ in
            for (index, glyph) in ordered.enumerated() {
                let x = CGFloat(index % perRow) * tileWidth
                let y = CGFloat(index / perRow) * tileHeight
                if !glyph.isEmpty {
                    let inset = centreWidth > 0 ? (content - (advances[glyph] ?? 0)) / 2 : 0
                    (glyph as NSString).draw(at: CGPoint(x: x + padding + inset, y: y + topOffset), withAttributes: attributes)
                }
                let rect = CGRect(
                    x: x / imageSize.width, y: y / imageSize.height,
                    width: tileWidth / imageSize.width, height: tileHeight / imageSize.height
                )
                rects[glyph] = rect
                glyphsByRect.append((rect, glyph))
            }
        }
        image = rendered.cgImage!
        self.rects = rects
        self.advances = advances
        self.glyphsByRect = glyphsByRect
        bytes = Int(imageSize.width * scale * imageSize.height * scale * 4)
    }

    func hasGlyph(_ glyph: String) -> Bool {
        rects[glyph] != nil
    }

    /// Normalised rect of the tile; the empty string maps to a blank tile.
    func contentsRect(_ glyph: String) -> CGRect {
        rects[glyph] ?? rects[""] ?? .zero
    }

    /// Advance of the glyph in points, letter spacing included, as the atlas measured it.
    func advance(_ glyph: String) -> CGFloat {
        advances[glyph] ?? 0
    }

    /// Reverse lookup used when a new plan interrupts a running one.
    func glyph(forContentsRect rect: CGRect) -> String? {
        // A presentation layer's rect comes back through float storage; match the tile it lies in.
        for (tile, glyph) in glyphsByRect
        where abs(tile.midX - rect.midX) < tile.width / 2 && abs(tile.midY - rect.midY) < tile.height / 2 {
            return glyph
        }
        return nil
    }
}
#endif
