#if os(iOS)
import SplitflapPlanner
import SwiftUI
import UIKit

/// Everything a board takes besides its text; set through the `splitflap…` modifiers and inherited
/// by every `Splitflap` below them.
/// Every setting the `splitflap…` modifiers write, read by each ``Splitflap`` below them. The
/// properties mean what the same-named ones on ``SplitflapView`` mean.
public struct SplitflapConfiguration {
    public var transition: SplitflapViewTransition = .reel()
    public var cellWidth: SplitflapCellWidth?
    public var duration: TimeInterval = defaultDurationMs / 1000
    public var stagger: TimeInterval = defaultStaggerMs / 1000
    public var staggerOrder: StaggerOrder = .ltr
    public var alphabet: AlphabetOption = .auto
    public var seed = 1
    public var isLoading = false
    public var loadingLength: LoadingLength?
    public var contentKey: AnyHashable?
    public var reduceMotion: SplitflapReduceMotion = .system
    public var animatesOnAppear = true
    public var font: UIFont = .systemFont(ofSize: 17)
    public var color: UIColor = .label
    public var letterSpacing: CGFloat = 0
    public var lineHeight: CGFloat?
    public var usesTabularDigits = true
    public var onTransitionStart: ((String) -> Void)?
    public var onTransitionEnd: ((String, Bool) -> Void)?

    public init() {}
}

private struct SplitflapConfigurationKey: EnvironmentKey {
    static var defaultValue: SplitflapConfiguration { SplitflapConfiguration() }
}

extension EnvironmentValues {
    /// The settings the `splitflap…` modifiers set for the views below them.
    public var splitflap: SplitflapConfiguration {
        get { self[SplitflapConfigurationKey.self] }
        set { self[SplitflapConfigurationKey.self] = newValue }
    }
}

extension SplitflapViewTransition {
    /// Flips over in halves; `surface` is the colour right under the text.
    // Disfavoured so that `.flip(surface: .black)` reads the UIColor case: both types have `.black`,
    // and without it the shortest spelling would not compile. A Color value still picks this one.
    @_disfavoredOverload
    public static func flip(surface: Color) -> SplitflapViewTransition {
        .flip(surface: UIColor(surface))
    }
}

/// Departure-board text: every changed letter rolls, flips or flickers into place, played by Core
/// Animation.
///
/// ```swift
/// Splitflap(gate)
///     .splitflapTransition(.flip(surface: .black))
///     .splitflapFont(size: 28, weight: .bold)
/// ```
public struct Splitflap: View {
    private let text: String
    @Environment(\.splitflap) private var configuration

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Board(text: text, configuration: configuration)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(text))
    }
}

private struct Board: UIViewRepresentable {
    let text: String
    let configuration: SplitflapConfiguration

    func makeUIView(context: Context) -> SplitflapView {
        let view = SplitflapView(frame: .zero)
        apply(to: view)
        return view
    }

    func updateUIView(_ view: SplitflapView, context: Context) {
        apply(to: view)
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SplitflapView, context: Context) -> CGSize? {
        let size = uiView.intrinsicContentSize
        guard let width = proposal.width, width < size.width else { return size }
        // Narrower than the text: the board ends in «…», as a one-line Text does.
        return CGSize(width: width, height: size.height)
    }

    private func apply(to view: SplitflapView) {
        let c = configuration
        view.font = c.font
        view.textColor = c.color
        view.letterSpacing = c.letterSpacing
        view.lineHeight = c.lineHeight
        view.usesTabularDigits = c.usesTabularDigits
        view.reduceMotion = c.reduceMotion
        view.animatesOnAppear = c.animatesOnAppear
        view.onTransitionStart = c.onTransitionStart
        view.onTransitionEnd = c.onTransitionEnd
        view.transition = c.transition
        view.cellWidth = c.cellWidth
        view.duration = c.duration
        view.stagger = c.stagger
        view.staggerOrder = c.staggerOrder
        view.alphabet = c.alphabet
        view.seed = c.seed
        view.loadingLength = c.loadingLength
        view.contentKey = c.contentKey
        view.isLoading = c.isLoading
        view.text = text
    }
}

extension View {
    private func splitflap(_ change: @escaping (inout SplitflapConfiguration) -> Void) -> some View {
        transformEnvironment(\.splitflap, transform: change)
    }

    /// How every changed letter moves: `.reel()` (the default), `.roll()`, `.flip(surface:)` or
    /// `.scramble`.
    public func splitflapTransition(_ transition: SplitflapViewTransition) -> some View {
        splitflap { $0.transition = transition }
    }

    /// How wide each cell is; without it each transition takes its best look.
    public func splitflapCellWidth(_ cellWidth: SplitflapCellWidth?) -> some View {
        splitflap { $0.cellWidth = cellWidth }
    }

    /// Seconds one cell takes, seconds between consecutive changed cells, and the order they start in.
    public func splitflapTiming(
        duration: TimeInterval = defaultDurationMs / 1000,
        stagger: TimeInterval = defaultStaggerMs / 1000,
        order: StaggerOrder = .ltr
    ) -> some View {
        splitflap {
            $0.duration = duration
            $0.stagger = stagger
            $0.staggerOrder = order
        }
    }

    /// The letters a cell travels through.
    public func splitflapAlphabet(_ alphabet: AlphabetOption) -> some View {
        splitflap { $0.alphabet = alphabet }
    }

    /// Seeds every random choice, so the same seed plays the same way.
    public func splitflapSeed(_ seed: Int) -> some View {
        splitflap { $0.seed = seed }
    }

    /// Loops random words of the text's script while `isLoading`; the real text then lands from
    /// whichever word is showing.
    public func splitflapLoading(_ isLoading: Bool, length: LoadingLength? = nil) -> some View {
        splitflap {
            $0.isLoading = isLoading
            $0.loadingLength = length
        }
    }

    /// Replans even if the text did not change: a reused row now showing another item.
    public func splitflapContentKey(_ key: AnyHashable?) -> some View {
        splitflap { $0.contentKey = key }
    }

    /// When the board skips its motion: `.system` follows the device's Reduce Motion setting, `.always`
    /// and `.never` override it.
    public func splitflapReduceMotion(_ reduceMotion: SplitflapReduceMotion) -> some View {
        splitflap { $0.reduceMotion = reduceMotion }
    }

    /// False shows the first text — and the first after the content key changes — at once.
    public func splitflapAnimatesOnAppear(_ animates: Bool) -> some View {
        splitflap { $0.animatesOnAppear = animates }
    }

    /// The font the glyphs are drawn in; scaled with Dynamic Type.
    public func splitflapFont(_ font: UIFont) -> some View {
        splitflap { $0.font = font }
    }

    /// The system font at this size, weight and design; scaled with Dynamic Type.
    public func splitflapFont(
        size: CGFloat, weight: UIFont.Weight = .regular, design: UIFontDescriptor.SystemDesign = .default
    ) -> some View {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let font = base.fontDescriptor.withDesign(design).map { UIFont(descriptor: $0, size: size) } ?? base
        return splitflap { $0.font = font }
    }

    /// The glyphs' colour.
    public func splitflapColor(_ color: Color) -> some View {
        splitflap { $0.color = UIColor(color) }
    }

    /// Extra space between glyphs, in points.
    public func splitflapLetterSpacing(_ spacing: CGFloat) -> some View {
        splitflap { $0.letterSpacing = spacing }
    }

    /// Digits of one width, so numbers keep still. On by default.
    public func splitflapTabularDigits(_ on: Bool) -> some View {
        splitflap { $0.usesTabularDigits = on }
    }

    /// A change began to animate, with the text it turns to. Not called when it shows at once.
    public func onSplitflapTransitionStart(_ action: @escaping (String) -> Void) -> some View {
        splitflap { $0.onTransitionStart = action }
    }

    /// The board settled on the text; `interrupted` when a newer text took over first.
    public func onSplitflapTransitionEnd(_ action: @escaping (_ text: String, _ interrupted: Bool) -> Void) -> some View {
        splitflap { $0.onTransitionEnd = action }
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("Departures") {
    @Previewable @State var gate = "GATE A3"
    VStack(alignment: .leading, spacing: 16) {
        Splitflap(gate)
            .splitflapTransition(.flip(surface: Color.black))
            .splitflapFont(size: 34, weight: .bold, design: .monospaced)
            .splitflapColor(.yellow)
        Splitflap("Lisboa → Madrid")
            .splitflapFont(size: 28, weight: .semibold)
        Button("Change") { gate = gate == "GATE A3" ? "GATE B12" : "GATE A3" }
    }
    .padding()
    .background(Color.black)
}
#endif
#endif
