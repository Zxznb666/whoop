import Foundation

/// 恢复分数的扣分项（PRD §5.8.2），单位与公式见注释。
public struct RecoveryPenalties: Sendable, Hashable, Codable {
    public var respiratory: Double
    public var temperature: Double
    public var oxygen: Double
    public var breathingDisturbance: Double

    public init(respiratory: Double = 0, temperature: Double = 0, oxygen: Double = 0, breathingDisturbance: Double = 0) {
        self.respiratory = respiratory
        self.temperature = temperature
        self.oxygen = oxygen
        self.breathingDisturbance = breathingDisturbance
    }

    /// - Parameters:
    ///   - zResp: 呼吸率 z-score
    ///   - temperatureDelta: 手腕温度偏差 Δt（°C）
    ///   - oxygenMedianPercent: 夜间血氧中位数（%）
    ///   - breathingElevated: 呼吸紊乱是否处于“升高”区间
    public static func make(
        zResp: Double?,
        temperatureDelta: Double?,
        oxygenMedianPercent: Double?,
        breathingElevated: Bool
    ) -> RecoveryPenalties {
        RecoveryPenalties(
            respiratory: zResp.map { min(0.6, 0.3 * max(0, $0 - 1.0)) } ?? 0,
            temperature: temperatureDelta.map { min(1.2, 0.8 * max(0, $0 - 0.3) / 0.5) } ?? 0,
            oxygen: oxygenMedianPercent.map { min(0.4, 0.1 * max(0, 95 - $0)) } ?? 0,
            breathingDisturbance: breathingElevated ? 0.2 : 0
        )
    }

    public var total: Double { respiratory + temperature + oxygen + breathingDisturbance }
}

/// 贡献拆解中的一项（瀑布图的一段）。
public struct RecoveryContribution: Sendable, Hashable, Codable {
    public var component: String
    /// 对分数的贡献（分）；所有项之和 = 未封顶的恢复分 − 基线 58.66
    public var points: Double

    public init(component: String, points: Double) {
        self.component = component
        self.points = points
    }
}

public enum RecoveryZone: String, Sendable, Hashable, Codable {
    case green
    case yellow
    case red
}

public struct RecoveryInputs: Sendable, Hashable {
    /// 原始 z-score（未截断）；为 nil 表示缺失
    public var zHRV: Double?
    public var zRHR: Double?
    public var zSleep: Double?
    public var penalties: RecoveryPenalties
    /// 生病预警进入“可能不适”，Recovery 封顶为 33
    public var illnessPossible: Bool

    public init(
        zHRV: Double?,
        zRHR: Double?,
        zSleep: Double?,
        penalties: RecoveryPenalties = RecoveryPenalties(),
        illnessPossible: Bool = false
    ) {
        self.zHRV = zHRV
        self.zRHR = zRHR
        self.zSleep = zSleep
        self.penalties = penalties
        self.illnessPossible = illnessPossible
    }
}

public struct RecoveryResult: Sendable, Hashable, Codable {
    /// 0–100，已应用封顶
    public var score: Double
    /// 未封顶的分数
    public var uncappedScore: Double
    /// 截断、矛盾处理之后实际参与计算的 z-score
    public var zHRV: Double
    public var zRHR: Double?
    public var zSleep: Double?
    public var penalties: RecoveryPenalties
    /// 各项归一化后的权重（只包含存在的分量）
    public var weights: [String: Double]
    /// Shapley 贡献：HRV、静息心率、睡眠、各扣分项
    public var contributions: [RecoveryContribution]
    public var contradiction: Bool
    public var capped: Bool
    public var zone: RecoveryZone

    public init(
        score: Double,
        uncappedScore: Double,
        zHRV: Double,
        zRHR: Double?,
        zSleep: Double?,
        penalties: RecoveryPenalties,
        weights: [String: Double],
        contributions: [RecoveryContribution],
        contradiction: Bool,
        capped: Bool,
        zone: RecoveryZone
    ) {
        self.score = score
        self.uncappedScore = uncappedScore
        self.zHRV = zHRV
        self.zRHR = zRHR
        self.zSleep = zSleep
        self.penalties = penalties
        self.weights = weights
        self.contributions = contributions
        self.contradiction = contradiction
        self.capped = capped
        self.zone = zone
    }
}

public enum RecoveryScorer {
    /// 基线：raw = 0 时的恢复分，约 58.66（PRD §5.8.3）
    public static let baseline = 100 / (1 + exp(-0.35))
    static let capValue = 33.0

    /// 返回 nil 表示没有 HRV（连 SDNN 也没有），不出分。
    public static func score(_ inputs: RecoveryInputs) -> RecoveryResult? {
        guard var zHRV = inputs.zHRV.map({ clip($0) }) else { return nil }
        var contradiction = false
        let zRHR = inputs.zRHR.map { clip($0) }
        let zSleep = inputs.zSleep.map { clip($0) }

        // 矛盾信号：HRV 异常偏高、但静息心率也偏高 → z_hrv 按 1 封顶
        if zHRV > 2, let zRHR, zRHR < -1 {
            zHRV = 1
            contradiction = true
        }

        // 缺失时把剩余分量的权重按比例放大，使总和为 1
        var base: [(name: String, z: Double, weight: Double)] = [("HRV", zHRV, 0.55)]
        if let zRHR { base.append(("静息心率", zRHR, 0.25)) }
        if let zSleep { base.append(("睡眠", zSleep, 0.20)) }
        let weightSum = base.reduce(0) { $0 + $1.weight }
        var weights: [String: Double] = [:]
        for item in base {
            weights[item.name] = item.weight / weightSum
        }

        let penalties = inputs.penalties
        let penaltyTerms: [(name: String, value: Double)] = [
            ("呼吸", penalties.respiratory),
            ("体温", penalties.temperature),
            ("血氧", penalties.oxygen),
            ("呼吸紊乱", penalties.breathingDisturbance),
        ]

        // 参与者：z 分量（只含存在的）+ 四个扣分项（为 0 时贡献为 0）
        let players: [(name: String, z: Double?, penalty: Double?)] =
            base.map { ($0.name, $0.z, nil) } + penaltyTerms.map { ($0.name, nil, $0.value) }

        func value(_ mask: Int) -> Double {
            var raw = 0.0
            for (index, player) in players.enumerated() where mask & (1 << index) != 0 {
                if let z = player.z, let weight = weights[player.name] {
                    raw += weight * z
                } else if let penalty = player.penalty {
                    raw -= penalty
                }
            }
            return 100 / (1 + exp(-(1.4 * raw + 0.35)))
        }

        let phi = shapley(count: players.count, value: value)
        let uncapped = value((1 << players.count) - 1)
        let capped = inputs.illnessPossible && uncapped > capValue
        let score = capped ? capValue : uncapped

        var contributions: [RecoveryContribution] = []
        for (index, player) in players.enumerated() {
            contributions.append(RecoveryContribution(component: player.name, points: phi[index]))
        }

        return RecoveryResult(
            score: score,
            uncappedScore: uncapped,
            zHRV: zHRV,
            zRHR: zRHR,
            zSleep: zSleep,
            penalties: penalties,
            weights: weights,
            contributions: contributions,
            contradiction: contradiction,
            capped: capped,
            zone: zone(for: score)
        )
    }

    /// 绿 ≥ 67；黄 34–66；红 ≤ 33（PRD §5.8.3）
    public static func zone(for score: Double) -> RecoveryZone {
        if score >= 67 { return .green }
        if score <= 33 { return .red }
        return .yellow
    }

    static func clip(_ z: Double) -> Double {
        min(max(z, -3), 3)
    }

    /// 精确 Shapley 值（PRD §5.8.4）。`value` 接收参与者位掩码，返回该子集下的分数。
    /// 参与者最多 7 个，共 2⁷ = 128 次求值。
    static func shapley(count n: Int, value: (Int) -> Double) -> [Double] {
        let values = (0..<(1 << n)).map(value)
        let factorial: [Double] = (0...n).map { k in (1...max(k, 1)).reduce(1.0) { $0 * Double($1) } }
        var phi = [Double](repeating: 0, count: n)
        for player in 0..<n {
            for mask in 0..<(1 << n) where mask & (1 << player) == 0 {
                let size = mask.nonzeroBitCount
                let weight = factorial[size] * factorial[n - size - 1] / factorial[n]
                phi[player] += weight * (values[mask | (1 << player)] - values[mask])
            }
        }
        return phi
    }
}
