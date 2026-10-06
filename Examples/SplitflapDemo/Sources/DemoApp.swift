import SplitflapKit
import SwiftUI
import UIKit

// The scenes of react-native-splitflap's showcase, so the two can be compared side by side. Launch
// with `-scene <id>` to open one scene directly (screenshots, recordings).

private let stage = Color(red: 0.114, green: 0.176, blue: 0.239)
private let amber = Color(red: 0.949, green: 0.761, blue: 0.188)

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            if let id = UserDefaults.standard.string(forKey: "scene"), let scene = DemoScene(rawValue: id) {
                SceneView(scene: scene)
            } else {
                NavigationStack {
                    List(DemoScene.allCases) { scene in
                        NavigationLink(scene.title) { SceneView(scene: scene).navigationTitle(scene.title) }
                    }
                    .navigationTitle("SplitflapKit")
                }
            }
        }
    }
}

enum DemoScene: String, CaseIterable, Identifiable {
    case transitions, scripts, numbers, departures, cellWidth = "cell-width", loading, uikit
    var id: String { rawValue }
    var title: String {
        switch self {
        case .transitions: "Four transitions"
        case .scripts: "Any script"
        case .numbers: "Numbers that hold still"
        case .departures: "Departures"
        case .cellWidth: "Cell width"
        case .loading: "Loading"
        case .uikit: "UIKit"
        }
    }
}

/// Advances every `interval` seconds; scenes read words by `step`.
@MainActor
final class Ticker: ObservableObject {
    @Published var step = 0
    private var timer: Timer?

    init(interval: TimeInterval) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step += 1 }
        }
    }
}

private func at<T>(_ items: [T], _ step: Int) -> T { items[step % items.count] }

/// Pads every word to the longest, as a real board has a fixed row of flaps.
private func fixed(_ words: [String]) -> [String] {
    let n = words.map(\.count).max() ?? 0
    return words.map { $0.padding(toLength: n, withPad: " ", startingAt: 0) }
}

struct SceneView: View {
    let scene: DemoScene

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(scene.title).font(.title2.bold()).foregroundStyle(amber)
                switch scene {
                case .transitions: TransitionsScene()
                case .scripts: ScriptsScene()
                case .numbers: NumbersScene()
                case .departures: DeparturesScene()
                case .cellWidth: CellWidthScene()
                case .loading: LoadingScene()
                case .uikit: UIKitScene().frame(height: 120)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(stage)
        .splitflapColor(.white)
        .splitflapFont(size: 30, weight: .bold)
    }
}

private struct Labelled<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
            content
        }
    }
}

private let cities = fixed(["MADRID", "BUENOS AIRES", "TOKYO", "LISBOA", "TBILISI"])

struct TransitionsScene: View {
    @StateObject private var ticker = Ticker(interval: 1.9)
    var body: some View {
        Labelled(label: "flip") {
            Splitflap(at(cities, ticker.step)).splitflapTransition(.flip(surface: stage))
        }
        Labelled(label: "reel") { Splitflap(at(cities, ticker.step)).splitflapTransition(.reel()) }
        Labelled(label: "roll") { Splitflap(at(cities, ticker.step)).splitflapTransition(.roll()) }
        Labelled(label: "scramble") { Splitflap(at(cities, ticker.step)).splitflapTransition(.scramble) }
    }
}

struct ScriptsScene: View {
    private let words = [
        "Wimbledon", "mañana", "привіт", "Ελλάδα", "ქართული", "नमस्ते", "สวัสดี", "ひらがな", "🇦🇷 👍🏽 1️⃣", "中文 한국어",
    ]
    @StateObject private var ticker = Ticker(interval: 1.7)
    var body: some View {
        Splitflap(at(words, ticker.step)).splitflapFont(size: 44, weight: .bold)
    }
}

struct NumbersScene: View {
    @StateObject private var ticker = Ticker(interval: 1.1)
    var body: some View {
        Labelled(label: "price") {
            Splitflap("$" + at(["1,299", "1,349", "1,319", "1,405", "1,388"], ticker.step)).splitflapTransition(.roll())
        }
        Labelled(label: "clock") { Splitflap(at(["12:40", "12:41", "12:42", "12:43", "12:44"], ticker.step)) }
        Labelled(label: "counter") { Splitflap(at(["0", "7", "42", "128", "365"], ticker.step)).splitflapTransition(.roll()) }
        Labelled(label: "devanagari · thai digits") {
            HStack(spacing: 24) {
                Splitflap(at(["१२३", "४५६", "७८९", "२४०"], ticker.step))
                Splitflap(at(["๑๒๓", "๔๕๖", "๗๘๙", "๒๔๐"], ticker.step))
            }
        }
    }
}

/// One flight on the board: time, flight, destination, gate.
private typealias Flight = [String]

/// Five rows, each two flights in turn: one boards and leaves, the next comes in delayed, boards
/// and leaves. The rows run a step apart, so every step exactly 13 of the 25 boards change — two
/// rows take a new flight (all five boards) and three move on a status.
private let rows: [(Flight, Flight)] = [
    (["12:40", "IB 6844", "🇪🇸 MADRID", "A3"], ["13:20", "AR 1133", "🇦🇷 BUENOS AIRES", "A7"]),
    (["12:55", "BA 247", "🇬🇧 LONDON", "B12"], ["13:35", "AF 1145", "🇫🇷 PARIS", "B16"]),
    (["13:05", "A9 651", "🇬🇪 TBILISI", "C7"], ["13:50", "LH 1709", "🇩🇪 MUNICH", "C11"]),
    (["13:15", "LA 2471", "🇵🇪 LIMA", "D2"], ["14:05", "TP 1351", "🇵🇹 LISBON", "D6"]),
    (["13:25", "JL 47", "🇯🇵 TOKYO", "E1"], ["14:20", "TK 1858", "🇹🇷 ISTANBUL", "E5"]),
]
private let statuses = ["DEPARTED ✈", "BOARDING", "DELAYED"]

/// A row's five steps: the second flight leaves, the first boards and leaves, the second comes in.
private func rowAt(_ row: Int, _ step: Int) -> [String] {
    let (first, second) = rows[row]
    let life: [(Flight, String)] = [
        (second, "DEPARTED ✈"), (first, "BOARDING"), (first, "DEPARTED ✈"), (second, "DELAYED"), (second, "BOARDING"),
    ]
    let (flight, status) = life[(step + row) % life.count]
    return flight + [status]
}

/// Each column as wide as its longest value, as a real board has a fixed row of flaps.
// Spelled out step by step: as one expression it is more than Xcode 16's type checker will solve.
private let widths: [Int] = {
    var widths: [Int] = []
    for column in 0..<4 {
        let values: [String] = rows.flatMap { [$0.0[column], $0.1[column]] }
        widths.append(values.map { $0.count }.max() ?? 0)
    }
    widths.append(statuses.map { $0.count }.max() ?? 0)
    return widths
}()

private func pad(_ text: String, _ width: Int) -> String {
    text + String(repeating: " ", count: max(0, width - text.count))
}

struct DeparturesScene: View {
    @StateObject private var ticker = Ticker(interval: 2.8)
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 10) {
                GridRow {
                    ForEach(["TIME", "FLIGHT", "DESTINATION", "GATE", "STATUS"], id: \.self) {
                        Text($0).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                ForEach(0..<rows.count, id: \.self) { row in
                    let values = rowAt(row, ticker.step)
                    GridRow {
                        ForEach(0..<5, id: \.self) { column in
                            // A flag is wider than a letter, and under .uniform it would widen every
                            // cell of the destination.
                            Splitflap(pad(values[column], widths[column]))
                                .splitflapColor(column == 4 ? amber : .white)
                                .splitflapCellWidth(column == 2 ? nil : .uniform)
                        }
                    }
                }
            }
        }
        .splitflapTransition(.flip(surface: stage))
        .splitflapFont(size: 11, weight: .bold, design: .monospaced)
    }
}

struct CellWidthScene: View {
    private let words = fixed(["mañana", "Wimbledon", "colectivo", "laburo"])
    @StateObject private var ticker = Ticker(interval: 1.8)
    var body: some View {
        ForEach(SplitflapCellWidth.allCases, id: \.self) { mode in
            Labelled(label: mode.rawValue) {
                Splitflap(at(words, ticker.step)).splitflapCellWidth(mode)
            }
        }
    }
}

struct LoadingScene: View {
    private let cities = ["Barcelona", "Lima", "Montevideo", "Oslo"]
    @StateObject private var ticker = Ticker(interval: 1.6)
    var body: some View {
        let loading = ticker.step % 2 == 0
        Labelled(label: loading ? "loading…" : "landed") {
            Splitflap(loading ? "" : at(cities, ticker.step / 2))
                .splitflapLoading(loading, length: .range(min: 4, max: 10))
        }
    }
}

struct UIKitScene: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        let board = SplitflapView(text: "UIKIT")
        board.font = .systemFont(ofSize: 40, weight: .heavy)
        board.textColor = .systemYellow
        board.transition = .flip(surface: UIColor(stage))
        board.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(board)
        NSLayoutConstraint.activate([
            board.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            board.centerYAnchor.constraint(equalTo: host.centerYAnchor),
        ])
        let words = ["UIKIT", "SWIFT", "IOS", "IPADOS", "SWIFTUI"]
        Task { @MainActor [weak board] in
            var step = 0
            while let board {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                step += 1
                board.text = words[step % words.count]
            }
        }
        return host
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
