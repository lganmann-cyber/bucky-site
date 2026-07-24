import Foundation

/// Deterministic RNG (SplitMix64). Every develop stores its seed so a re-render
/// of the same photo with the same seed is pixel-stable, while a "re-roll"
/// simply draws a new seed.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }

    /// Uniform in [range.lowerBound, range.upperBound).
    mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    /// True with probability p.
    mutating func chance(_ p: Double) -> Bool { unit() < p }

    mutating func pick<T>(_ items: [T]) -> T? {
        guard !items.isEmpty else { return nil }
        return items[Int(next() % UInt64(items.count))]
    }

    static func freshSeed() -> UInt64 {
        UInt64.random(in: UInt64.min...UInt64.max)
    }
}
