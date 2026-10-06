# Recipes

Short, complete examples for the common jobs: a departure board, prices, clocks, loading, lists, UIKit and the planner.

## A departure board: one transition for the whole board

Modifiers flow down to every `Splitflap` inside, and the nearest one wins, so a column can still take its own colour.

```swift
struct Departures: View {
    let flights: [(time: String, city: String, status: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(flights, id: \.city) { flight in
                HStack(spacing: 12) {
                    Splitflap(flight.time)
                    Splitflap(flight.city)
                    Splitflap(flight.status).splitflapColor(.yellow)
                }
            }
        }
        .splitflapTransition(.flip(surface: .black))
        .splitflapCellWidth(.uniform)
        .splitflapFont(size: 20, weight: .bold, design: .monospaced)
        .splitflapColor(.white)
    }
}
```

## A price that holds still

Digits are tabular by default, so the price keeps its width; `.auto` rolls each digit the short way round.

```swift
struct Price: View {
    let amount: Decimal

    var body: some View {
        Splitflap(amount.formatted(.currency(code: "USD")))
            .splitflapTransition(.roll(direction: .auto))
            .splitflapFont(size: 34, weight: .semibold)
    }
}
```

## A clock

```swift
struct Clock: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Splitflap(context.date.formatted(date: .omitted, time: .standard))
                .splitflapTransition(.reel(direction: .down))
                .splitflapCellWidth(.uniform)
        }
    }
}
```

## Loading words instead of a skeleton

Random words spin while the data loads, then the real text lands. The range keeps the loading words near the size of what comes.

```swift
struct Greeting: View {
    let name: String?

    var body: some View {
        Splitflap(name ?? "")
            .splitflapLoading(name == nil, length: .range(min: 4, max: 10))
            .splitflapTransition(.flip(surface: .black))
    }
}
```

## Hex codes, a custom alphabet and timing

```swift
struct Status: View {
    let code: String

    var body: some View {
        Splitflap(code)
            .splitflapTransition(.scramble)
            .splitflapAlphabet(.letters("0123456789ABCDEF"))
            .splitflapTiming(duration: 0.4, stagger: 0.02, order: .random)
    }
}
```

## One script for every cell

By default each letter rolls through its own script's alphabet, read from the text; name a script to fix it.

```swift
struct City: View {
    let name: String

    var body: some View {
        Splitflap(name)
            .splitflapAlphabet(.script(.greek))
    }
}
```

## Rows in a list

A reused row replans when its key changes, and shows its first text at once instead of animating in.

```swift
struct Row: View {
    let item: (id: Int, title: String)

    var body: some View {
        Splitflap(item.title)
            .splitflapContentKey(item.id)
            .splitflapAnimatesOnAppear(false)
    }
}
```

## Knowing when a change starts and settles

```swift
struct Score: View {
    let score: Int
    @State private var settled = true

    var body: some View {
        Splitflap(String(score))
            .onSplitflapTransitionStart { _ in settled = false }
            .onSplitflapTransitionEnd { _, interrupted in
                if !interrupted { settled = true }
            }
            .opacity(settled ? 1 : 0.8)
    }
}
```

## Motion, randomness and tracking

`.never` keeps the motion even with Reduce Motion on — for a decorative banner only. The same seed always plays the same way.

```swift
struct Banner: View {
    var body: some View {
        Splitflap("SALE")
            .splitflapReduceMotion(.never)
            .splitflapSeed(7)
            .splitflapLetterSpacing(2)
    }
}
```

## UIKit: a view controller with loading

`SplitflapView` sizes itself like a one-line `UILabel`, so Auto Layout needs only a position.

```swift
final class GateViewController: UIViewController {
    private let board = SplitflapView(text: "")

    override func viewDidLoad() {
        super.viewDidLoad()
        board.font = .monospacedSystemFont(ofSize: 28, weight: .bold)
        board.textColor = .systemYellow
        board.transition = .flip(surface: .black)
        board.cellWidth = .uniform
        board.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(board)
        NSLayoutConstraint.activate([
            board.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            board.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        board.isLoading = true
        board.loadingLength = .cells(6)
        board.onTransitionEnd = { text, interrupted in
            print("settled on \(text)", interrupted ? "(interrupted)" : "")
        }
    }

    func show(gate: String) {
        board.isLoading = false
        board.text = gate
    }
}
```

## The planner, without a view

`SplitflapPlanner` (re-exported by `SplitflapKit`) returns every cell's path and timing as plain data — for tests, or to draw the board some other way.

```swift
func plannedPaths() {
    let first = planTransition(createBoard(), TransitionInput(text: "MADRID", now: 0, instant: true))
    let next = planTransition(first.board, TransitionInput(text: "LISBOA", now: 1000, transition: .flip))
    for cell in next.plan.cells {
        print(cell.from, "→", cell.to, cell.path.joined(), "\(cell.delayMs) ms")
    }
}
```
