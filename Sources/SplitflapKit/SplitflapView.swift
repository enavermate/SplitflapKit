#if os(iOS)
import SplitflapPlanner
import UIKit

/// How every changed letter of a board moves.
public enum SplitflapViewTransition: Equatable {
    /// Spins through the alphabet between the old letter and the new one, like a slot machine reel.
    case reel(direction: Direction = .random)
    /// Rolls through a few letters: its neighbours when the new one is close, random ones when far.
    case roll(direction: Direction = .random)
    /// Flips over in halves, like a departure board. `surface` is the colour right under the text:
    /// the flaps are painted with it, so the half they cover never shows through.
    case flip(surface: UIColor)
    /// Flickers through random letters of its own script, then locks.
    case scramble

    var planner: SplitflapTransition {
        switch self {
        case .reel: return .reel
        case .roll: return .roll
        case .flip: return .flip
        case .scramble: return .scramble
        }
    }

    var direction: Direction? {
        switch self {
        case .reel(let d), .roll(let d): return d
        case .flip, .scramble: return nil
        }
    }

    /// Each transition's best look; `flip` and `scramble` show two glyphs in one cell at once, so
    /// they never reflow like text.
    var defaultCellWidth: CellMode {
        switch self {
        case .reel, .roll: return .natural
        case .flip, .scramble: return .tiered
        }
    }
}

/// When the board skips its motion.
public enum SplitflapReduceMotion: Sendable {
    /// Follows the device's Reduce Motion setting.
    case system
    /// Shows every change at once.
    case always
    /// Always animates.
    case never
}

private let maskFade: CGFloat = 0.16
// A mask never resizes with its cell, so it is simply wider than any cell can be.
private let maskWidth: CGFloat = 4096
// A centred cell shifts its bounds' origin by at most half the widest cell; the mask starts well
// left of that, so the shift never uncovers an edge.
private let maskOrigin: CGFloat = -maskWidth / 2
// A cell's width settles a little after its glyph.
private let widthWindow = 1.15
private let sampleHz = 120.0
private let maxSamples = 2000
private let flipPerspective: CGFloat = 220
// The top flap folds toward the viewer.
private let flapFold = -1.0
private let scrambleDim: Float = 0.55
private let scrambleMaxSteps = 2000
private let ellipsis = "…"

private enum Renderer {
    case drum, scramble, flip

    init(_ transition: SplitflapTransition) {
        switch transition {
        case .scramble: self = .scramble
        case .flip: self = .flip
        case .reel, .roll: self = .drum
        }
    }
}

private func noActions() -> [String: any CAAction] {
    let keys = [
        "position", "bounds", "contents", "contentsRect", "contentsScale", "hidden", "sublayers",
        "onOrderIn", "onOrderOut", "mask", "opacity", "transform", "sublayerTransform",
        "backgroundColor", "anchorPoint",
    ]
    return Dictionary(uniqueKeysWithValues: keys.map { ($0, NSNull() as any CAAction) })
}

/// Glyph layers A and B alternate along a path: even glyphs on A, odd on B.
private func glyphOfLayer(_ segment: Int, _ isLayerA: Bool) -> Int {
    let even = segment % 2 == 0
    return isLayerA ? (even ? segment : segment + 1) : (even ? segment + 1 : segment)
}

/// Perspective for a cell's sublayers with the vanishing point at the cell's centre.
private func perspective(_ distance: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CATransform3D {
    var p = CATransform3DIdentity
    p.m34 = -1 / distance
    let toCentre = CATransform3DMakeTranslation(-width / 2, -height / 2, 0)
    let back = CATransform3DMakeTranslation(width / 2, height / 2, 0)
    return CATransform3DConcat(CATransform3DConcat(toCentre, p), back)
}

/// Angle about X of a presented transform whose rotation part is a pure X rotation.
private func rotationX(_ t: CATransform3D) -> Double {
    atan2(Double(t.m23), Double(t.m22))
}

private func topHalf(_ r: CGRect) -> CGRect {
    CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height / 2)
}

private func bottomHalf(_ r: CGRect) -> CGRect {
    CGRect(x: r.minX, y: r.minY + r.height / 2, width: r.width, height: r.height / 2)
}

private func easeValue(_ e: Easing, _ x: Double) -> Double {
    ease(e, min(1, max(0, x)))
}

private func easeInv(_ e: Easing, _ p: Double) -> Double {
    easeInverse(e, min(1, max(0, p)))
}

@MainActor
private final class Cell {
    let container = CALayer()
    let mask = CAGradientLayer()
    let a = CALayer()
    let b = CALayer()
    /// The two flaps of a flip.
    let c = CALayer()
    let d = CALayer()
    /// Model width, where the cell settles once its plan is over.
    var width: CGFloat = 0

    var glyphLayers: [CALayer] { [a, b, c, d] }

    init(in parent: CALayer) {
        container.anchorPoint = .zero
        container.masksToBounds = true
        container.actions = noActions()
        // Each drum cell keeps its own fade: one mask over the whole board measured slower with
        // sixty boards, as any moving cell then redraws every cell under it.
        mask.anchorPoint = .zero
        mask.startPoint = CGPoint(x: 0.5, y: 0)
        mask.endPoint = CGPoint(x: 0.5, y: 1)
        mask.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        mask.locations = [0, NSNumber(value: Double(maskFade)), NSNumber(value: Double(1 - maskFade)), 1]
        mask.actions = noActions()
        container.mask = mask
        for layer in glyphLayers {
            layer.anchorPoint = .zero
            layer.actions = noActions()
            container.addSublayer(layer)
        }
        c.isHidden = true
        d.isHidden = true
        parent.addSublayer(container)
    }

    func removeAllAnimations() {
        container.removeAllAnimations()
        for layer in glyphLayers { layer.removeAllAnimations() }
    }
}

/// What an interrupted cell showed at the moment the new plan arrived.
private struct Presented {
    var width: CGFloat?
    /// drum: y of each glyph currently on a layer.
    var glyphYs: [String: CGFloat] = [:]
    /// flip: which flap is mid-fold, showing which glyph, at which angle.
    var topGlyph: String?
    var topAngle: Double?
    var bottomGlyph: String?
    var bottomAngle: Double?
    /// scramble: the cell was flickering.
    var dimmed = false
}

/// Departure-board text: every changed letter rolls, flips or flickers into place, played by Core
/// Animation. Lays out like a one-line `UILabel` of the same font, «…» included.
@MainActor
open class SplitflapView: UIView {
    // MARK: - What the board shows

    /// What the board shows. A new text turns in from the one on screen; a change mid-flight
    /// continues from where every cell is.
    public var text: String = "" { didSet { if text != oldValue { planChanged() } } }
    /// Loops random words of the text's script until it turns false; the real text then lands from
    /// whichever word is showing.
    public var isLoading = false { didSet { if isLoading != oldValue { planChanged() } } }
    /// The loading words' length: `.cells(n)` for exactly n cells, `.range(min:max:)` for lengths
    /// drawn from the range the real text may come in. Without it the words wander ±1 around the
    /// text's length.
    public var loadingLength: LoadingLength? { didSet { if loadingLength != oldValue { planChanged() } } }
    /// Replans even if `text` did not change: a reused table or collection view cell now showing
    /// another item.
    public var contentKey: AnyHashable? { didSet { if contentKey != oldValue { planChanged() } } }

    // MARK: - How it moves

    /// How every changed letter moves: `.reel()` (the default), `.roll()`, `.flip(surface:)` or
    /// `.scramble`.
    public var transition: SplitflapViewTransition = .reel() {
        didSet { if transition != oldValue { planChanged(); styleChanged() } }
    }
    /// How wide each cell is; nil takes the transition's best look. `natural` applies to `reel` and
    /// `roll` only.
    public var cellWidth: SplitflapCellWidth? { didSet { if cellWidth != oldValue { styleChanged() } } }
    /// Seconds one cell takes; `flip` takes 1.6 times this.
    public var duration: TimeInterval = defaultDurationMs / 1000 { didSet { if duration != oldValue { planChanged() } } }
    /// Seconds between the starts of consecutive changed cells.
    public var stagger: TimeInterval = defaultStaggerMs / 1000 { didSet { if stagger != oldValue { planChanged() } } }
    /// The order the changed cells start in: `.ltr`, `.rtl` or `.random`.
    public var staggerOrder: StaggerOrder = .ltr { didSet { if staggerOrder != oldValue { planChanged() } } }
    /// The letters a cell travels through.
    public var alphabet: AlphabetOption = .auto { didSet { if alphabet != oldValue { planChanged() } } }
    /// Seeds every random choice, so the same seed plays the same way.
    public var seed = 1 { didSet { if seed != oldValue { planChanged() } } }
    /// When the board skips its motion: `.system` follows the device's Reduce Motion setting, `.always`
    /// and `.never` override it.
    public var reduceMotion: SplitflapReduceMotion = .system
    /// False shows the first text — and the first after `contentKey` changes — at once.
    public var animatesOnAppear = true

    // MARK: - How it looks

    /// The font the glyphs are drawn in; scaled with Dynamic Type.
    public var font: UIFont = .systemFont(ofSize: 17) { didSet { styleChanged() } }
    /// The glyphs' colour.
    public var textColor: UIColor = .label { didSet { styleChanged() } }
    /// Extra space between glyphs, in points.
    public var letterSpacing: CGFloat = 0 { didSet { if letterSpacing != oldValue { styleChanged() } } }
    /// The line height every cell is laid out on; nil takes the font's.
    public var lineHeight: CGFloat? { didSet { if lineHeight != oldValue { styleChanged() } } }
    /// Digits of one width, so numbers keep still. On by default.
    public var usesTabularDigits = true { didSet { if usesTabularDigits != oldValue { styleChanged() } } }
    /// Scales the font with Dynamic Type, as a label set to adjust does.
    public var adjustsFontForContentSizeCategory = true {
        didSet { if adjustsFontForContentSizeCategory != oldValue { styleChanged() } }
    }

    // MARK: - Events

    /// A change began to animate. Not called when it shows at once.
    public var onTransitionStart: ((String) -> Void)?
    /// The board settled on the text; `interrupted` when a newer text took over first.
    public var onTransitionEnd: ((String, Bool) -> Void)?

    // MARK: - State

    private var cells: [Cell] = []
    private var board = createBoard()
    private var plannedOnce = false
    private var plannedContentKey: AnyHashable?
    private var planDirty = true
    private var styleDirty = true
    private var resolvedFont: UIFont = .systemFont(ofSize: 17)
    private var resolvedColor: UIColor = .label
    private var atlas: GlyphAtlas?
    private var measured = Measured()
    private var measuredKey = ""
    private var textGlyphs: [String] = []
    private var visible: Int?
    private var generation = 0
    private var inFlight = false
    private var inFlightText: String?
    private var inFlightRenderer: Renderer = .drum
    /// The transition of the last plan; a flip board keeps its tiles at rest.
    private var styleTransition: SplitflapTransition = .roll
    private var lastFrame: CGRect = .zero
    private var lastWidth: CGFloat = 0
    private var lastVisible: Int?
    /// While loading, the widest loading word: the text is usually empty then, and a board of no
    /// width would be clipped by any container that clips (SwiftUI does).
    private var loadingWidth: CGFloat = 0
    /// A plan made for the current settings and not played yet: planning happens as soon as the
    /// size is asked for, so the size can count the loading words; playing waits for layout.
    private var pending: Plan?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    public convenience init(text: String) {
        self.init(frame: .zero)
        self.text = text
    }

    private func setUp() {
        layer.actions = noActions()
        // A leaving word can be wider than the new frame for a moment; each cell still clips its own
        // glyphs.
        clipsToBounds = false
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        if #available(iOS 17.0, *) {
            registerForTraitChanges(
                [UITraitPreferredContentSizeCategory.self, UITraitUserInterfaceStyle.self, UITraitDisplayScale.self]
            ) { (view: SplitflapView, _: UITraitCollection) in
                view.styleChanged()
            }
        }
    }

    open override var accessibilityLabel: String? {
        get { super.accessibilityLabel ?? text }
        set { super.accessibilityLabel = newValue }
    }

    private func planChanged() {
        planDirty = true
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func styleChanged() {
        styleDirty = true
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    @available(iOS, deprecated: 17.0)
    open override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if #available(iOS 17.0, *) { return }
        if previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory
            || previous?.hasDifferentColorAppearance(comparedTo: traitCollection) == true
            || previous?.displayScale != traitCollection.displayScale
        {
            styleChanged()
        }
    }

    // MARK: - Layout

    private var resolvedCellWidth: CellMode {
        let fallback = transition.defaultCellWidth
        switch cellWidth {
        case .uniform: return .uniform
        // `flip` and `scramble` show two glyphs in one cell at once and never reflow.
        case .natural, nil: return fallback
        }
    }

    private func resolveStyle() {
        var f = font
        if usesTabularDigits {
            let tabular = f.fontDescriptor.addingAttributes([
                .featureSettings: [[
                    UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                    UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
                ]],
            ])
            f = UIFont(descriptor: tabular, size: f.pointSize)
        }
        if adjustsFontForContentSizeCategory {
            f = UIFontMetrics.default.scaledFont(for: f, compatibleWith: traitCollection)
        }
        resolvedFont = f
        resolvedColor = textColor.resolvedColor(with: traitCollection)
        atlas = nil
    }

    private func remeasure() {
        let glyphs = splitGlyphs(text)
        let mode = resolvedCellWidth
        let key = "\(text)\u{0}\(mode)\u{0}\(resolvedFont.fontName)\u{0}\(resolvedFont.pointSize)\u{0}\(letterSpacing)\u{0}\(lineHeight ?? -1)\u{0}\(usesTabularDigits)"
        textGlyphs = glyphs
        if key != measuredKey {
            measuredKey = key
            measured = Measure.measure(
                glyphs: glyphs, text: text, mode: mode,
                font: resolvedFont, letterSpacing: letterSpacing, lineHeight: lineHeight
            )
        }
    }

    open override var intrinsicContentSize: CGSize {
        if styleDirty { resolveStyle() }
        remeasure()
        planIfNeeded()
        let width = isLoading ? max(measured.total, loadingWidth) : measured.total
        return CGSize(width: ceil(width), height: measured.lineHeight)
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        intrinsicContentSize
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        let restyled = styleDirty
        if styleDirty {
            resolveStyle()
            styleDirty = false
        }
        let before = measured
        remeasure()
        visible = Measure.visibleCount(
            measured, glyphs: textGlyphs, available: bounds.width,
            font: resolvedFont, letterSpacing: letterSpacing
        )
        let frameMove = frameMovement()
        lastFrame = frame

        planIfNeeded()
        if let plan = pending {
            pending = nil
            if plan.cells.count < textGlyphs.count {
                showTextInstantly(text)
            } else {
                play(plan, text: text, frameMove: frameMove)
            }
        } else if restyled || before != measured || visible != lastVisible || bounds.width != lastWidth {
            if isLoading {
                // Loading words are motion, not text: a new font or size restarts them.
                planDirty = true
                planIfNeeded()
                if let plan = pending {
                    pending = nil
                    play(plan, text: text, frameMove: nil)
                }
            } else {
                showTextInstantly(text)
            }
        }
        lastWidth = bounds.width
        lastVisible = visible
    }

    /// A new text resizes the frame at once, and a container that centres it moves its left edge
    /// with it: drawn from the new edge, the old word would hop sideways before a single cell turned.
    /// The anchor is read off the move itself, so any alignment is kept.
    private func frameMovement() -> (shift: CGFloat, anchor: CGFloat)? {
        let grown = frame.width - lastFrame.width
        let shift = lastFrame.minX - frame.minX
        guard lastFrame.width > 0, abs(grown) > 0.5, abs(shift) > 0.01 else { return nil }
        let anchor = shift / grown
        guard anchor > -0.05, anchor < 1.05 else { return nil }
        return (shift, min(1, max(0, anchor)))
    }

    // MARK: - Planning

    private func planIfNeeded() {
        guard planDirty else { return }
        planDirty = false
        let now = CACurrentMediaTime() * 1000
        let firstShow = !plannedOnce || plannedContentKey != contentKey
        let result: (plan: Plan, board: Board)
        if isLoading {
            let length = loadingLength ?? .cells(textGlyphs.isEmpty ? 6 : textGlyphs.count)
            var exact = false
            if case .cells = loadingLength { exact = true }
            result = loadingPlan(
                length, seed: seed,
                options: LoadingOptions(
                    now: now, alphabet: alphabet, text: text, transition: transition.planner, exactLength: exact
                )
            )
        } else {
            result = planTransition(
                board,
                TransitionInput(
                    text: text, now: now, transition: transition.planner,
                    duration: duration * 1000, stagger: stagger * 1000, staggerOrder: staggerOrder,
                    direction: transition.direction, alphabet: alphabet, seed: seed,
                    instant: !animatesOnAppear && firstShow
                )
            )
        }
        board = result.board
        let widest = isLoading ? widestWord(of: result.plan) : 0
        if widest != loadingWidth {
            loadingWidth = widest
            invalidateIntrinsicContentSize()
        }
        plannedOnce = true
        plannedContentKey = contentKey
        styleTransition = result.plan.transition
        pending = result.plan
    }

    /// The widest word a looping plan shows, in the board's font.
    private func widestWord(of plan: Plan) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: resolvedFont, .kern: letterSpacing]
        guard let steps = plan.cells.map(\.path.count).max() else { return 0 }
        return (0..<steps).map { k in
            plan.cells.reduce(CGFloat(0)) { sum, cell in
                sum + (k < cell.path.count ? Measure.width(cell.path[k], attributes) : 0)
            }
        }.max() ?? 0
    }

    // MARK: - Atlas and cells

    private var scale: CGFloat {
        let s = traitCollection.displayScale
        return s > 0 ? s : 2
    }

    private func atlas(for glyphs: Set<String>) -> GlyphAtlas {
        let a = GlyphAtlas.atlas(
            font: resolvedFont, color: resolvedColor, letterSpacing: letterSpacing,
            lineHeight: measured.lineHeight, scale: scale, centreWidth: measured.centreWidth, glyphs: glyphs
        )
        atlas = a
        return a
    }

    /// A cell `width` wide. The atlas draws each glyph centred in `centreWidth`; the bounds' origin
    /// shifts that span so its middle is the cell's middle, whatever width the cell has right now.
    private func cellBounds(width: CGFloat, height: CGFloat) -> CGRect {
        let centre = measured.centreWidth
        return CGRect(x: centre > 0 ? (centre - width) / 2 : 0, y: 0, width: width, height: height)
    }

    private var surfaceColor: UIColor {
        if case .flip(let surface) = transition { return surface.resolvedColor(with: traitCollection) }
        // Only a flip paints its flaps; any other board never reads this.
        return (backgroundColor ?? .clear).resolvedColor(with: traitCollection)
    }

    /// The measured width when the cell shows a glyph of the measured text; a loading word or a
    /// leaving glyph falls back to the atlas advance, which the same font produced.
    private func settledWidth(_ glyph: String, at index: Int) -> CGFloat {
        if glyph.isEmpty { return 0 }
        if index < textGlyphs.count, textGlyphs[index] == glyph, index < measured.cellWidths.count {
            return measured.cellWidths[index]
        }
        return atlas?.advance(glyph) ?? 0
    }

    private func ensureCellCount(_ count: Int) {
        while cells.count < count { cells.append(Cell(in: layer)) }
        while cells.count > count {
            let cell = cells.removeLast()
            cell.removeAllAnimations()
            cell.container.removeFromSuperlayer()
        }
    }

    /// The drum look of a cell: masked, flat, two full-tile glyph layers. Every renderer starts here.
    private func applyAtlas(_ atlas: GlyphAtlas, to cell: Cell) {
        let height = atlas.tileHeight
        cell.mask.frame = CGRect(x: maskOrigin, y: 0, width: maskWidth, height: height)
        cell.container.mask = cell.mask
        cell.container.sublayerTransform = CATransform3DIdentity
        for layer in cell.glyphLayers {
            layer.contents = atlas.image
            layer.contentsScale = atlas.scale
            layer.contentsGravity = .resize
            layer.anchorPoint = .zero
            layer.bounds = CGRect(x: 0, y: 0, width: atlas.tileWidth, height: height)
            layer.position = CGPoint(x: -atlas.padding, y: layer.position.y)
            layer.transform = CATransform3DIdentity
            layer.opacity = 1
            layer.backgroundColor = nil
            layer.isDoubleSided = true
            layer.isHidden = false
        }
        cell.c.isHidden = true
        cell.d.isHidden = true
    }

    /// The split-flap look: two static halves (A top, B bottom), two flaps hinged on the middle line
    /// (C top, D bottom), perspective from the cell centre, no drum mask.
    private func configureFlip(_ cell: Cell, atlas: GlyphAtlas, width: CGFloat, surface: UIColor) {
        let height = atlas.tileHeight
        let half = height / 2
        let centreX = -atlas.padding + atlas.tileWidth / 2
        cell.container.mask = nil
        cell.container.sublayerTransform = perspective(flipPerspective, width, height)
        // The halves take the surface colour, so the half a flap covers never shows through.
        for layer in cell.glyphLayers {
            layer.bounds = CGRect(x: 0, y: 0, width: atlas.tileWidth, height: half)
            layer.backgroundColor = surface.cgColor
            layer.isHidden = false
        }
        cell.a.position = CGPoint(x: -atlas.padding, y: 0)
        cell.b.position = CGPoint(x: -atlas.padding, y: half)
        cell.c.anchorPoint = CGPoint(x: 0.5, y: 1)
        cell.c.position = CGPoint(x: centreX, y: half)
        cell.c.isDoubleSided = false
        cell.c.opacity = 0
        cell.d.anchorPoint = CGPoint(x: 0.5, y: 0)
        cell.d.position = CGPoint(x: centreX, y: half)
        cell.d.isDoubleSided = false
        cell.d.opacity = 0
    }

    /// A cell at rest on `glyph`, in the drum look or, for a flip board, on its two halves.
    private func settle(_ cell: Cell, on glyph: String, atlas: GlyphAtlas, flip: Bool) {
        let rect = atlas.contentsRect(glyph)
        if flip {
            cell.a.contentsRect = topHalf(rect)
            cell.b.contentsRect = bottomHalf(rect)
            return
        }
        cell.a.contentsRect = rect
        cell.a.position = CGPoint(x: -atlas.padding, y: 0)
        cell.b.contentsRect = atlas.contentsRect("")
        cell.b.position = CGPoint(x: -atlas.padding, y: -atlas.tileHeight)
    }

    // MARK: - Events

    private var reducesMotion: Bool {
        switch reduceMotion {
        case .always: return true
        case .never: return false
        case .system: return UIAccessibility.isReduceMotionEnabled
        }
    }

    private func finishInstantly(_ text: String) {
        generation += 1
        let current = generation
        inFlight = false
        inFlightText = nil
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == current else { return }
            self.onTransitionEnd?(text, false)
        }
    }

    private func interruptIfInFlight() {
        guard inFlight else { return }
        let text = inFlightText ?? ""
        inFlight = false
        inFlightText = nil
        onTransitionEnd?(text, true)
    }

    /// The text with no motion: Reduce Motion, a style change or a new size.
    private func showTextInstantly(_ text: String) {
        interruptIfInFlight()
        var glyphs = textGlyphs
        if let visible { glyphs = Array(glyphs.prefix(visible)) + [ellipsis] }
        let atlas = atlas(for: Set(glyphs))
        let flip = Renderer(styleTransition) == .flip
        let surface = surfaceColor

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ensureCellCount(glyphs.count)
        var x: CGFloat = 0
        for (i, glyph) in glyphs.enumerated() {
            let cell = cells[i]
            cell.removeAllAnimations()
            applyAtlas(atlas, to: cell)
            let width = settledWidth(glyph, at: i)
            cell.width = width
            cell.container.bounds = cellBounds(width: width, height: atlas.tileHeight)
            cell.container.position = CGPoint(x: x, y: 0)
            if flip { configureFlip(cell, atlas: atlas, width: width, surface: surface) }
            settle(cell, on: glyph, atlas: atlas, flip: flip)
            x += width
        }
        CATransaction.commit()
        finishInstantly(text)
    }

    // MARK: - Drum

    private struct LayerTrack {
        var keyTimesY: [Double] = []
        var valuesY: [CGFloat] = []
        var keyTimesRect: [Double] = []
        var valuesRect: [CGRect] = []
        var finalY: CGFloat = 0
        var finalRect: CGRect = .zero
    }

    private func drumTrack(
        _ plan: CellPlan, isLayerA: Bool, window: Double, height: CGFloat, atlas: GlyphAtlas, resumeOffset: CGFloat
    ) -> LayerTrack {
        var track = LayerTrack()
        let steps = plan.land
        let delay = plan.delayMs
        let duration = plan.durationMs
        let dir = CGFloat(plan.dir)
        let path = plan.path
        func glyph(_ index: Int) -> String { path.indices.contains(index) ? path[index] : "" }
        func yOf(_ glyphIndex: Int, _ s: Double) -> CGFloat { dir * CGFloat(Double(glyphIndex) - s) * height }

        let first = glyphOfLayer(0, isLayerA)
        let startY = yOf(first, 0) + resumeOffset
        track.keyTimesY += [0, delay / window]
        track.valuesY += [startY, startY]
        track.keyTimesRect.append(0)
        track.valuesRect.append(atlas.contentsRect(glyph(first)))

        var lastY = startY
        var lastTime = delay
        for k in 0..<steps {
            let from = delay + duration * easeInv(plan.easing, Double(k) / Double(steps))
            let to = delay + duration * easeInv(plan.easing, Double(k + 1) / Double(steps))
            let g = glyphOfLayer(k, isLayerA)
            if k > 0, g != glyphOfLayer(k - 1, isLayerA) {
                track.keyTimesY.append(min(1, from / window + keyTimeEpsilon))
                track.valuesY.append(yOf(g, Double(k)))
                track.keyTimesRect.append(from / window)
                track.valuesRect.append(atlas.contentsRect(glyph(g)))
            }
            let samples = Int(min(60, max(3, ceil((to - from) / 8))))
            for q in 1...samples {
                let t = from + (to - from) * Double(q) / Double(samples)
                let s = Double(steps) * easeValue(plan.easing, (t - delay) / duration)
                let blend = k == 0 ? resumeOffset * CGFloat(1 - min(1, s)) : 0
                lastY = yOf(g, s) + blend
                lastTime = t
                track.keyTimesY.append(min(1, t / window))
                track.valuesY.append(lastY)
            }
        }
        if lastTime < window {
            track.keyTimesY.append(1)
            track.valuesY.append(lastY)
        }
        track.keyTimesRect.append(1)
        track.finalY = lastY
        track.finalRect = track.valuesRect.last ?? .zero
        return track
    }

    private func add(_ track: LayerTrack, to layer: CALayer, window: Double, beginTime: CFTimeInterval, loop: Bool) {
        let y = CAKeyframeAnimation(keyPath: "position.y")
        y.keyTimes = track.keyTimesY.map { NSNumber(value: $0) }
        y.values = track.valuesY.map { NSNumber(value: Double($0)) }
        y.calculationMode = .linear
        y.duration = window / 1000
        y.beginTime = beginTime
        y.fillMode = .backwards
        y.repeatCount = loop ? .infinity : 0
        layer.add(y, forKey: "splitflap.y")
        if track.valuesRect.count > 1 {
            let rect = CAKeyframeAnimation(keyPath: "contentsRect")
            rect.keyTimes = track.keyTimesRect.map { NSNumber(value: $0) }
            rect.values = track.valuesRect.map { NSValue(cgRect: $0) }
            rect.calculationMode = .discrete
            rect.duration = window / 1000
            rect.beginTime = beginTime
            rect.fillMode = .backwards
            rect.repeatCount = loop ? .infinity : 0
            layer.add(rect, forKey: "splitflap.rect")
        }
        layer.position = CGPoint(x: layer.position.x, y: track.finalY)
        layer.contentsRect = track.finalRect
    }

    private func playDrum(
        _ plan: CellPlan, cell: Cell, atlas: GlyphAtlas, window: Double, beginTime: CFTimeInterval,
        loop: Bool, presented: Presented
    ) {
        let height = atlas.tileHeight
        // An interrupted cell keeps rolling from where its visible glyph is, not from a jump to 0.
        var resumeOffset: CGFloat = 0
        if let y = presented.glyphYs[plan.path[0]], abs(y) < height { resumeOffset = y }
        let trackA = drumTrack(plan, isLayerA: true, window: window, height: height, atlas: atlas, resumeOffset: resumeOffset)
        let trackB = drumTrack(plan, isLayerA: false, window: window, height: height, atlas: atlas, resumeOffset: resumeOffset)
        add(trackA, to: cell.a, window: window, beginTime: beginTime, loop: loop)
        add(trackB, to: cell.b, window: window, beginTime: beginTime, loop: loop)
    }

    // MARK: - Scramble

    /// One glyph layer flickers through letters of the target's script every stepMs, dimmed, and
    /// locks on the landing glyph. The letters come from a small LCG seeded by the cell index, so a
    /// replan shows the same flicker. An empty target fades out instead.
    private func playScramble(
        _ plan: CellPlan, cell: Cell, index: Int, atlas: GlyphAtlas, window: Double,
        beginTime: CFTimeInterval, loop: Bool, presented: Presented
    ) {
        cell.container.mask = nil
        let from = plan.path[0]
        let to = plan.path[plan.land]
        let delay = plan.delayMs
        let lock = delay + plan.durationMs
        func rect(_ glyph: String) -> NSValue { NSValue(cgRect: atlas.contentsRect(glyph)) }

        var rects = Track(window: window, discrete: true)
        if to.isEmpty {
            var opacity = Track(window: window, discrete: false)
            rects.add(0, rect(from))
            opacity.add(0, NSNumber(value: 1))
            opacity.add(delay, NSNumber(value: 1))
            opacity.add(lock, NSNumber(value: 0))
            rects.add(lock, rect(""))
            rects.add(to: cell.a, keyPath: "contentsRect", beginTime: beginTime, loop: loop)
            opacity.add(to: cell.a, keyPath: "opacity", beginTime: beginTime, loop: loop)
        } else {
            var opacity = Track(window: window, discrete: true)
            let letters = (plan.letters ?? "").map(String.init)
            let pool = letters.isEmpty ? [to] : letters
            let start = presented.dimmed ? 0 : delay
            if start > 0 {
                rects.add(0, rect(from))
                opacity.add(0, NSNumber(value: 1))
            }
            opacity.add(start, NSNumber(value: scrambleDim))
            var state: UInt32 = 0x9E37_79B9 ^ (UInt32(truncatingIfNeeded: index + 1) &* 0x85EB_CA6B)
            var t = start
            var count = 0
            let step = max(1, plan.stepMs ?? 55)
            while t < lock, count < scrambleMaxSteps {
                state = state &* 1_664_525 &+ 1_013_904_223
                rects.add(t, rect(pool[Int((state >> 8) % UInt32(pool.count))]))
                t += step
                count += 1
            }
            rects.add(lock, rect(to))
            opacity.add(lock, NSNumber(value: 1))
            rects.add(to: cell.a, keyPath: "contentsRect", beginTime: beginTime, loop: loop)
            opacity.add(to: cell.a, keyPath: "opacity", beginTime: beginTime, loop: loop)
        }
        settle(cell, on: to, atlas: atlas, flip: false)
    }

    // MARK: - Flip

    /// Per step of the path: A shows the next glyph's top half, B the current glyph's bottom half;
    /// the top flap C folds 0 → 90° about the hinge in the first half of the step, then the bottom
    /// flap D drops 90° → 0 in the second. A flap caught mid-fold continues from its presented angle.
    private func playFlip(
        _ plan: CellPlan, cell: Cell, atlas: GlyphAtlas, window: Double, beginTime: CFTimeInterval,
        loop: Bool, presented: Presented
    ) {
        let steps = plan.land
        let delay = plan.delayMs
        let duration = plan.durationMs
        let path = plan.path
        func glyph(_ i: Int) -> String { path.indices.contains(i) ? path[i] : "" }
        func top(_ i: Int) -> NSValue { NSValue(cgRect: topHalf(atlas.contentsRect(glyph(i)))) }
        func bottom(_ i: Int) -> NSValue { NSValue(cgRect: bottomHalf(atlas.contentsRect(glyph(i)))) }
        let folded = flapFold * .pi / 2
        let raised = -flapFold * .pi / 2

        var resumeTop = false
        if let angle = presented.topAngle, presented.topGlyph == path[0], angle * flapFold > 0, abs(angle) < .pi / 2 {
            resumeTop = true
        }
        var resumeBottom = false
        if !resumeTop, let angle = presented.bottomAngle, presented.bottomGlyph == path[0], angle * flapFold < 0,
            abs(angle) < .pi / 2
        {
            resumeBottom = true
        }

        var aRect = Track(window: window, discrete: true)
        var bRect = Track(window: window, discrete: true)
        var cRect = Track(window: window, discrete: true)
        var dRect = Track(window: window, discrete: true)
        var cOpacity = Track(window: window, discrete: true)
        var dOpacity = Track(window: window, discrete: true)
        var cAngle = Track(window: window, discrete: false)
        var dAngle = Track(window: window, discrete: false)
        func num(_ v: Double) -> NSNumber { NSNumber(value: v) }

        aRect.add(0, top(resumeTop ? 1 : 0))
        bRect.add(0, bottom(0))
        cRect.add(0, top(0))
        cOpacity.add(0, num(resumeTop ? 1 : 0))
        cAngle.add(0, num(resumeTop ? presented.topAngle! : 0))
        dRect.add(0, bottom(0))
        dOpacity.add(0, num(resumeBottom ? 1 : 0))
        dAngle.add(0, num(resumeBottom ? presented.bottomAngle! : raised))

        for k in 0..<steps {
            let from = delay + duration * easeInv(plan.easing, Double(k) / Double(steps))
            let to = delay + duration * easeInv(plan.easing, Double(k + 1) / Double(steps))
            let mid = (from + to) / 2

            aRect.add(from, top(k + 1))
            bRect.add(from, bottom(k))

            cRect.add(from, top(k))
            cOpacity.add(from, num(1))
            cAngle.add(from, num(k == 0 && resumeTop ? presented.topAngle! : 0))
            cAngle.add(mid, num(folded))
            cOpacity.add(mid, num(0))
            cAngle.add(mid, num(0))

            if k == 0 && resumeBottom {
                // The previous plan's bottom flap lands while this plan's top flap already falls.
                dRect.add(from, bottom(0))
                dOpacity.add(from, num(1))
                dAngle.add(from, num(presented.bottomAngle!))
                dAngle.add(mid, num(0))
                dRect.add(mid, bottom(1))
                dAngle.add(mid, num(raised))
            } else {
                dRect.add(from, bottom(k + 1))
                dOpacity.add(from, num(0))
                dAngle.add(from, num(raised))
                dOpacity.add(mid, num(1))
                dAngle.add(mid, num(raised))
            }
            dAngle.add(to, num(0))
            dOpacity.add(to, num(0))
        }
        bRect.add(delay + duration, bottom(steps))

        aRect.add(to: cell.a, keyPath: "contentsRect", beginTime: beginTime, loop: loop)
        bRect.add(to: cell.b, keyPath: "contentsRect", beginTime: beginTime, loop: loop)
        cRect.add(to: cell.c, keyPath: "contentsRect", beginTime: beginTime, loop: loop)
        cOpacity.add(to: cell.c, keyPath: "opacity", beginTime: beginTime, loop: loop)
        cAngle.add(to: cell.c, keyPath: "transform.rotation.x", beginTime: beginTime, loop: loop)
        dRect.add(to: cell.d, keyPath: "contentsRect", beginTime: beginTime, loop: loop)
        dOpacity.add(to: cell.d, keyPath: "opacity", beginTime: beginTime, loop: loop)
        dAngle.add(to: cell.d, keyPath: "transform.rotation.x", beginTime: beginTime, loop: loop)

        settle(cell, on: glyph(steps), atlas: atlas, flip: true)
        if let last = cRect.last as? NSValue { cell.c.contentsRect = last.cgRectValue }
        if let last = dRect.last as? NSValue { cell.d.contentsRect = last.cgRectValue }
    }

    // MARK: - Playing a plan

    private func capturePresented(for renderer: Renderer) -> [Presented] {
        let same = inFlightRenderer == renderer
        return cells.map { cell in
            var state = Presented()
            let container = cell.container.presentation() ?? cell.container
            state.width = container.bounds.width
            guard same, let atlas else { return state }
            switch renderer {
            case .drum:
                for glyphLayer in [cell.a, cell.b] {
                    let layer = glyphLayer.presentation() ?? glyphLayer
                    if let glyph = atlas.glyph(forContentsRect: layer.contentsRect), state.glyphYs[glyph] == nil {
                        state.glyphYs[glyph] = layer.position.y
                    }
                }
            case .flip:
                let top = cell.c.presentation() ?? cell.c
                if top.opacity > 0.5 {
                    state.topGlyph = atlas.glyph(forContentsRect: top.contentsRect)
                    state.topAngle = rotationX(top.transform)
                }
                let bottom = cell.d.presentation() ?? cell.d
                if bottom.opacity > 0.5 {
                    state.bottomGlyph = atlas.glyph(forContentsRect: bottom.contentsRect)
                    state.bottomAngle = rotationX(bottom.transform)
                }
            case .scramble:
                let layer = cell.a.presentation() ?? cell.a
                state.dimmed = layer.opacity < 1
            }
            return state
        }
    }

    /// The plan cut to its first `count` cells, the last landing on "…": tail truncation applied to
    /// an animation, so it ends on what a label would show.
    private func truncated(_ plan: Plan, to count: Int) -> Plan {
        guard count > 0, count < plan.cells.count else { return plan }
        var copy = plan
        copy.cells = Array(plan.cells.prefix(count))
        var last = copy.cells[count - 1]
        last.path[last.land] = ellipsis
        last.to = ellipsis
        last.letters = nil
        copy.cells[count - 1] = last
        return copy
    }

    private func play(_ planIn: Plan, text: String, frameMove: (shift: CGFloat, anchor: CGFloat)?) {
        let renderer = Renderer(planIn.transition)
        let flip = renderer == .flip
        var presented: [Presented] = []
        if inFlight, atlas != nil { presented = capturePresented(for: renderer) }
        interruptIfInFlight()
        generation += 1

        var plan = planIn
        if let visible { plan = truncated(plan, to: visible + 1) }

        var glyphSet = Set(textGlyphs)
        for cellPlan in plan.cells {
            glyphSet.formUnion(cellPlan.path)
            if renderer == .scramble, !cellPlan.to.isEmpty, cellPlan.land > 0 {
                glyphSet.formUnion((cellPlan.letters ?? "").map(String.init))
            }
        }
        let atlas = atlas(for: glyphSet)
        let height = atlas.tileHeight
        let count = plan.cells.count
        let surface = surfaceColor
        let loop = plan.loop ?? false

        var window = reducesMotion ? 0 : plan.totalMs
        if window > 0 {
            for cellPlan in plan.cells { window = max(window, cellPlan.delayMs + cellPlan.durationMs * widthWindow) }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ensureCellCount(count)

        var startWidths = [CGFloat](repeating: 0, count: count)
        var targetWidths = [CGFloat](repeating: 0, count: count)
        for i in 0..<count {
            let cellPlan = plan.cells[i]
            startWidths[i] = (i < presented.count ? presented[i].width : nil) ?? cells[i].width
            targetWidths[i] = settledWidth(cellPlan.path[cellPlan.land], at: i)
        }
        // `uniform`: the widest glyph on each cell's way, held while the glyphs turn.
        // `tiered` holds only the wider of its two ends: a roll through «m» would otherwise widen a
        // narrow cell on every turn.
        let mode = resolvedCellWidth
        let tiered = mode == .tiered
        let stable = mode == .uniform || tiered
        var holdWidths = [CGFloat](repeating: 0, count: count)
        if stable {
            for i in 0..<count {
                let cellPlan = plan.cells[i]
                var widest = max(startWidths[i], targetWidths[i])
                if !tiered {
                    for glyph in cellPlan.path { widest = max(widest, atlas.advance(glyph)) }
                    if renderer == .scramble, !cellPlan.to.isEmpty, cellPlan.land > 0 {
                        for glyph in (cellPlan.letters ?? "").map(String.init) { widest = max(widest, atlas.advance(glyph)) }
                    }
                }
                holdWidths[i] = widest
            }
        }
        func widthAt(_ i: Int, _ t: Double) -> CGFloat {
            let cellPlan = plan.cells[i]
            if loop {
                // Loading words: every cell is as wide as the word on screen, easing to the next one
                // as it turns — a loop has no start and end width to travel between.
                let pos = positionAt(BoardCell(cell: cellPlan, startMs: 0, loopMs: nil), t)
                let path = cellPlan.path
                let here = settledWidth(path[min(pos.k, path.count - 1)], at: i)
                guard pos.moving, pos.k + 1 < path.count else { return here }
                let next = settledWidth(path[pos.k + 1], at: i)
                return here + (next - here) * CGFloat(easeValue(.inOut, pos.f))
            }
            if stable {
                // Opens to the hold width in the first sixth of the turn, holds while the glyphs
                // move, and narrows to the landed glyph after they stop.
                let start = cellPlan.delayMs
                let open = cellPlan.durationMs / 6
                let land = start + cellPlan.durationMs
                let close = land + cellPlan.durationMs * (widthWindow - 1)
                if t <= start || cellPlan.durationMs <= 0 { return t <= start ? startWidths[i] : targetWidths[i] }
                if t < start + open {
                    let p = easeValue(.inOut, (t - start) / open)
                    return startWidths[i] + (holdWidths[i] - startWidths[i]) * CGFloat(p)
                }
                if t < land { return holdWidths[i] }
                if t >= close { return targetWidths[i] }
                let p = easeValue(.inOut, (t - land) / (close - land))
                return holdWidths[i] + (targetWidths[i] - holdWidths[i]) * CGFloat(p)
            }
            let span = cellPlan.durationMs * widthWindow
            if t < cellPlan.delayMs { return startWidths[i] }
            if span <= 0 || t >= cellPlan.delayMs + span { return targetWidths[i] }
            let p = easeValue(.inOut, (t - cellPlan.delayMs) / span)
            return startWidths[i] + (targetWidths[i] - startWidths[i]) * CGFloat(p)
        }

        if window > 0 {
            let current = generation
            CATransaction.setCompletionBlock { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == current else { return }
                    self.inFlight = false
                    self.inFlightText = nil
                    self.onTransitionEnd?(text, false)
                }
            }
        }

        let beginTime = CACurrentMediaTime()
        let sampleCount = min(maxSamples, Int(max(2, ceil(window / 1000 * sampleHz) + 1)))
        var anyWidthChanges = false
        var finalX: CGFloat = 0
        // Where the word's left edge is drawn at `t`, against the new frame: where the old word stood,
        // moving to 0 as the content takes the new width, around the container's anchor.
        let carried = frameMove != nil && window > 0
        func contentAt(_ t: Double) -> CGFloat { (0..<count).reduce(0) { $0 + widthAt($1, t) } }
        let startContent = carried ? contentAt(0) : 0
        func offsetAt(_ t: Double) -> CGFloat {
            guard let move = frameMove, carried else { return 0 }
            return move.shift - move.anchor * (contentAt(t) - startContent)
        }

        for i in 0..<count {
            let cellPlan = plan.cells[i]
            let cell = cells[i]
            cell.removeAllAnimations()
            applyAtlas(atlas, to: cell)

            let widthChanges = loop || startWidths[i] != targetWidths[i] || (stable && holdWidths[i] != targetWidths[i])
            if window > 0, widthChanges || anyWidthChanges || carried {
                var keyTimes: [NSNumber] = []
                var boundsValues: [NSValue] = []
                var xs: [NSNumber] = []
                for q in 0..<sampleCount {
                    let t = window * Double(q) / Double(sampleCount - 1)
                    var x = offsetAt(t)
                    for j in 0..<i { x += widthAt(j, t) }
                    keyTimes.append(NSNumber(value: Double(q) / Double(sampleCount - 1)))
                    boundsValues.append(NSValue(cgRect: cellBounds(width: widthAt(i, t), height: height)))
                    xs.append(NSNumber(value: Double(x)))
                }
                if widthChanges {
                    let animation = CAKeyframeAnimation(keyPath: "bounds")
                    animation.keyTimes = keyTimes
                    animation.values = boundsValues
                    animation.calculationMode = .linear
                    animation.duration = window / 1000
                    animation.beginTime = beginTime
                    animation.fillMode = .backwards
                    animation.repeatCount = loop ? .infinity : 0
                    cell.container.add(animation, forKey: "splitflap.bounds")
                }
                if anyWidthChanges || carried {
                    let animation = CAKeyframeAnimation(keyPath: "position.x")
                    animation.keyTimes = keyTimes
                    animation.values = xs
                    animation.calculationMode = .linear
                    animation.duration = window / 1000
                    animation.beginTime = beginTime
                    animation.fillMode = .backwards
                    animation.repeatCount = loop ? .infinity : 0
                    cell.container.add(animation, forKey: "splitflap.x")
                }
            }
            anyWidthChanges = anyWidthChanges || widthChanges
            cell.width = targetWidths[i]
            cell.container.bounds = cellBounds(width: targetWidths[i], height: height)
            cell.container.position = CGPoint(x: finalX, y: 0)
            finalX += targetWidths[i]

            if flip { configureFlip(cell, atlas: atlas, width: targetWidths[i], surface: surface) }

            let steps = cellPlan.land
            if window == 0 || steps == 0 || cellPlan.durationMs <= 0 {
                settle(cell, on: cellPlan.path[steps], atlas: atlas, flip: flip)
                continue
            }
            let cellPresented = i < presented.count ? presented[i] : Presented()
            switch renderer {
            case .scramble:
                playScramble(cellPlan, cell: cell, index: i, atlas: atlas, window: window, beginTime: beginTime, loop: loop, presented: cellPresented)
            case .flip:
                playFlip(cellPlan, cell: cell, atlas: atlas, window: window, beginTime: beginTime, loop: loop, presented: cellPresented)
            case .drum:
                playDrum(cellPlan, cell: cell, atlas: atlas, window: window, beginTime: beginTime, loop: loop, presented: cellPresented)
            }
        }
        CATransaction.commit()

        if window > 0 {
            inFlight = true
            inFlightText = text
            inFlightRenderer = renderer
            onTransitionStart?(text)
        } else {
            finishInstantly(text)
        }
    }
}
#endif
