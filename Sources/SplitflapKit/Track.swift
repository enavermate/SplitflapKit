#if os(iOS)
import QuartzCore

/// Two keyframes this close together are one instantaneous jump (a glyph swap between layers).
let keyTimeEpsilon = 1e-6

/// One keyframe animation of any property over a plan window, in milliseconds. Key times stay
/// strictly increasing: a value added at a time already used lands an epsilon later, which Core
/// Animation plays as an instantaneous jump. A discrete track owns the extra trailing key time Core
/// Animation wants for that mode.
struct Track {
    private(set) var times: [Double] = []
    private(set) var values: [Any] = []
    let window: Double
    let discrete: Bool

    init(window: Double, discrete: Bool) {
        self.window = window
        self.discrete = discrete
    }

    mutating func add(_ ms: Double, _ value: Any) {
        var t = window > 0 ? min(1, max(0, ms / window)) : 0
        let ceiling = discrete ? 1 - keyTimeEpsilon : 1
        t = min(t, ceiling)
        if let last = times.last {
            if t <= last { t = last + keyTimeEpsilon }
            if t > ceiling {
                values[values.count - 1] = value
                return
            }
        }
        times.append(t)
        values.append(value)
    }

    var last: Any? { values.last }

    func add(to layer: CALayer, keyPath: String, beginTime: CFTimeInterval, loop: Bool) {
        guard let lastValue = values.last else { return }
        var keyTimes = times
        var values = self.values
        if discrete {
            keyTimes.append(1)
        } else if (keyTimes.last ?? 1) < 1 {
            keyTimes.append(1)
            values.append(lastValue)
        }
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.keyTimes = keyTimes.map { NSNumber(value: $0) }
        animation.values = values
        animation.calculationMode = discrete ? .discrete : .linear
        animation.duration = window / 1000
        animation.beginTime = beginTime
        animation.fillMode = .backwards
        animation.repeatCount = loop ? .infinity : 0
        layer.add(animation, forKey: "splitflap.\(keyPath)")
    }
}
#endif
