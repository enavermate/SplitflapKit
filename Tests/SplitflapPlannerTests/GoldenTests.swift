import Foundation
import XCTest

@testable import SplitflapPlanner

// The planner is a port of react-native-splitflap's TypeScript planner. planner.json is produced
// there (src/__tests__/planner-golden.test.ts) and timeline.json is the Android player's fixture: the
// same scenarios must give the same plans here, so a board looks the same on every platform.
final class GoldenTests: XCTestCase {
    private func fixture(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Resources/\(name)", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func alphabet(_ value: Any?) -> AlphabetOption? {
        if let name = value as? String {
            return name == "auto" ? .auto : SplitflapScript(rawValue: name).map(AlphabetOption.script)
        }
        if let object = value as? [String: Any], let letters = object["letters"] as? String {
            return .letters(letters)
        }
        return nil
    }

    private func input(_ o: [String: Any]) -> TransitionInput {
        TransitionInput(
            text: o["text"] as! String,
            now: (o["now"] as! NSNumber).doubleValue,
            transition: (o["transition"] as? String).flatMap(SplitflapTransition.init),
            duration: (o["duration"] as? NSNumber)?.doubleValue,
            stagger: (o["stagger"] as? NSNumber)?.doubleValue,
            staggerOrder: (o["staggerOrder"] as? String).flatMap(StaggerOrder.init),
            direction: (o["direction"] as? String).flatMap(Direction.init),
            alphabet: alphabet(o["alphabet"]),
            seed: (o["seed"] as? NSNumber)?.intValue,
            instant: o["instant"] as? Bool ?? false
        )
    }

    private func loading(_ o: [String: Any]) -> (LoadingLength, Int, LoadingOptions) {
        let length: LoadingLength
        if let n = o["length"] as? NSNumber {
            length = .cells(n.intValue)
        } else {
            let r = o["length"] as! [String: NSNumber]
            length = .range(min: r["min"]!.doubleValue, max: r["max"]!.doubleValue)
        }
        let opt = o["options"] as! [String: Any]
        let options = LoadingOptions(
            now: (opt["now"] as! NSNumber).doubleValue,
            alphabet: alphabet(opt["alphabet"]),
            text: opt["text"] as? String,
            wordMs: (opt["wordMs"] as? NSNumber)?.doubleValue,
            transition: (opt["transition"] as? String).flatMap(SplitflapTransition.init),
            exactLength: opt["exactLength"] as? Bool ?? false
        )
        return (length, (o["seed"] as! NSNumber).intValue, options)
    }

    private func check(_ actual: CellPlan, _ expected: CellPlan, _ at: String) {
        XCTAssertEqual(actual.i, expected.i, at)
        XCTAssertTrue(same(actual.from, expected.from), "\(at) from \(actual.from) ≠ \(expected.from)")
        XCTAssertTrue(same(actual.to, expected.to), "\(at) to \(actual.to) ≠ \(expected.to)")
        XCTAssertEqual(actual.path.count, expected.path.count, "\(at) path \(actual.path) ≠ \(expected.path)")
        for (a, e) in zip(actual.path, expected.path) {
            XCTAssertTrue(same(a, e), "\(at) path \(actual.path) ≠ \(expected.path)")
        }
        XCTAssertEqual(actual.delayMs, expected.delayMs, at)
        XCTAssertEqual(actual.durationMs, expected.durationMs, at)
        XCTAssertEqual(actual.easing, expected.easing, at)
        XCTAssertEqual(actual.dir, expected.dir, at)
        XCTAssertEqual(actual.stepMs, expected.stepMs, at)
        XCTAssertTrue(same(actual.letters ?? "", expected.letters ?? "") && (actual.letters == nil) == (expected.letters == nil), "\(at) letters")
        XCTAssertEqual(actual.land, expected.land, at)
        XCTAssertEqual(actual.resume?.k, expected.resume?.k, "\(at) resume")
        XCTAssertEqual(actual.resume?.f ?? -1, expected.resume?.f ?? -1, accuracy: 1e-9, "\(at) resume")
    }

    func testPlannerScenarios() throws {
        let golden = try fixture("planner")
        let scenarios = golden["scenarios"] as! [[String: Any]]
        XCTAssertEqual(scenarios.count, 131)
        for scenario in scenarios {
            let name = scenario["name"] as! String
            let steps = scenario["steps"] as! [[String: Any]]
            let results = scenario["results"] as! [[String: Any]]
            var board = createBoard()
            for (n, step) in steps.enumerated() {
                let result: (plan: Plan, board: Board)
                if step["op"] as? String == "plan" {
                    result = planTransition(board, input(step["input"] as! [String: Any]))
                } else {
                    let (length, seed, options) = loading(step)
                    result = loadingPlan(length, seed: seed, options: options)
                }
                board = result.board
                let expectedPlan = try decode(Plan.self, results[n]["plan"]!)
                let expectedBoard = try decode(Board.self, results[n]["board"]!)
                let at = "\(name) step \(n)"
                XCTAssertEqual(result.plan.transition, expectedPlan.transition, at)
                XCTAssertEqual(result.plan.totalMs, expectedPlan.totalMs, at)
                XCTAssertEqual(result.plan.loop, expectedPlan.loop, at)
                XCTAssertEqual(result.plan.cells.count, expectedPlan.cells.count, "\(at) cells")
                for (a, e) in zip(result.plan.cells, expectedPlan.cells) { check(a, e, "\(at) cell \(e.i)") }
                XCTAssertEqual(result.board.revision, expectedBoard.revision, at)
                XCTAssertEqual(result.board.cells.map(\.startMs), expectedBoard.cells.map(\.startMs), at)
                XCTAssertEqual(result.board.cells.map(\.loopMs), expectedBoard.cells.map(\.loopMs), at)
            }
        }
    }

    func testSplitGlyphs() throws {
        for sample in try fixture("planner")["splitGlyphs"] as! [[String: Any]] {
            let text = sample["text"] as! String
            let expected = sample["glyphs"] as! [String]
            let actual = splitGlyphs(text)
            XCTAssertEqual(actual.count, expected.count, text)
            for (a, e) in zip(actual, expected) { XCTAssertTrue(same(a, e), "\(text): \(actual) ≠ \(expected)") }
        }
    }

    func testWidthGlyphs() throws {
        for sample in try fixture("planner")["widthGlyphs"] as! [[String: Any]] {
            let text = sample["text"] as! String
            XCTAssertTrue(same(widthGlyphs(text), sample["glyphs"] as! String), text)
        }
    }

    func testRandom() throws {
        let golden = try fixture("planner")
        for sample in golden["hash"] as! [[String: Any]] {
            let parts = (sample["parts"] as! [NSNumber]).map(\.intValue)
            let value = (sample["value"] as! NSNumber).uint32Value
            var h: UInt32 = 0x811c_9dc5
            for part in parts {
                h ^= UInt32(truncatingIfNeeded: Int32(truncatingIfNeeded: part))
                h = h &* 0x9e37_79b1
                h ^= h >> 15
            }
            XCTAssertEqual(h, value, "\(parts)")
            if parts.count == 3 { XCTAssertEqual(SplitflapPlanner.hash(parts[0], parts[1], parts[2]), value) }
        }
        for sample in golden["mulberry32"] as! [[String: Any]] {
            let rng = Rng(seed: (sample["seed"] as! NSNumber).uint32Value)
            for expected in sample["values"] as! [NSNumber] {
                // Each value is an integer over 2^32; Foundation's JSON parser can miss the last digit
                // of the decimal, so the integers are compared.
                XCTAssertEqual((rng.next() * 4_294_967_296).rounded(), (expected.doubleValue * 4_294_967_296).rounded())
            }
        }
    }

    func testTimeline() throws {
        let golden = try fixture("timeline")
        let easing = golden["easing"] as! [String: [NSNumber]]
        let xs = easing["xs"]!.map(\.doubleValue)
        for name in ["out", "inOut", "linear"] {
            for (x, y) in zip(xs, easing[name]!) {
                XCTAssertEqual(ease(Easing(rawValue: name)!, x), y.doubleValue, accuracy: 1e-12, "\(name)(\(x))")
            }
        }
        for c in golden["cases"] as! [[String: Any]] {
            let plan = try JSONDecoder().decode(Plan.self, from: Data((c["plan"] as! String).utf8))
            let times = (c["times"] as! [NSNumber]).map(\.doubleValue)
            let progress = c["progress"] as! [[NSNumber]]
            for (cell, row) in zip(plan.cells, progress) {
                for (t, p) in zip(times, row) {
                    let pos = positionAt(BoardCell(cell: cell, startMs: 0, loopMs: nil), t)
                    XCTAssertEqual(Double(pos.k) + pos.f, p.doubleValue, accuracy: 1e-9, "cell \(cell.i) at \(t)")
                }
            }
        }
    }
}
