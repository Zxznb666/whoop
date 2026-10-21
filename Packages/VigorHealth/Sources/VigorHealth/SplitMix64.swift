import Foundation

/// SplitMix64 伪随机数生成器。同一种子生成的序列完全一致，保证合成数据可复现。
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// [0, 1) 上的均匀分布。
    mutating func unit() -> Double {
        Double(next() >> 11) / 9_007_199_254_740_992
    }

    mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit()
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }
}

