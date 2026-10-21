import Foundation
import Testing
@testable import VigorScoring

@Suite("DataQuality")
struct QualityTests {
    private func hrv(night: Int, morning: Int = 0, sdnn: Double? = nil, dispersion: Double? = nil) -> NightHRV {
        NightHRV(
            nightRMSSD: night > 0 ? 30 : nil,
            nightValidCount: night,
            nightTotalCount: night,
            morningRMSSD: morning > 0 ? 40 : nil,
            morningValidCount: morning,
            sdnnMean: sdnn,
            dispersion: dispersion,
            method: .overnight
        )
    }

    @Test("Q_hrv：3 段及以上 1.0；2 段 0.7；1 段 0.4；只有 SDNN 0.3；都没有 0")
    func hrvBySegmentCount() {
        #expect(DataQualityScorer.hrvComponent(hrv(night: 3)) == 1)
        #expect(DataQualityScorer.hrvComponent(hrv(night: 2)) == 0.7)
        #expect(DataQualityScorer.hrvComponent(hrv(night: 1)) == 0.4)
        #expect(DataQualityScorer.hrvComponent(hrv(night: 0, sdnn: 40)) == 0.3)
        #expect(DataQualityScorer.hrvComponent(hrv(night: 0)) == 0)
    }

    @Test("Q_hrv：有晨测直接取 1.0；段间离散度 > 0.4 时乘 0.8")
    func hrvMorningAndDispersion() {
        #expect(DataQualityScorer.hrvComponent(hrv(night: 1, morning: 1)) == 1)
        #expect(abs(DataQualityScorer.hrvComponent(hrv(night: 3, dispersion: 0.5)) - 0.8) < 1e-9)
        #expect(DataQualityScorer.hrvComponent(hrv(night: 3, dispersion: 0.4)) == 1)
    }

    @Test("总质量等级：≥ 0.75 高；0.5–0.75 中；< 0.5 低")
    func levels() {
        #expect(DataQualityScorer.level(for: 0.75) == .high)
        #expect(DataQualityScorer.level(for: 0.74) == .medium)
        #expect(DataQualityScorer.level(for: 0.5) == .medium)
        #expect(DataQualityScorer.level(for: 0.49) == .low)
    }
}
