import Foundation

// ITU-T P.1203 MOS estimation (rescaled G.107 E-model) — returns [1.0, 5.0].
internal enum MosCalculator {
    static func calculate(latencyMs: Double, jitterMs: Double, lossPercent: Double) -> Double {
        let effectiveLatency = latencyMs + jitterMs * 2 + 10
        var r: Double
        if effectiveLatency < 160 {
            r = 93.2 - effectiveLatency / 40
        } else {
            r = 93.2 - effectiveLatency / 120 - 10
        }
        r -= lossPercent * 2.5
        let raw: Double
        if r < 0 { raw = 1.0 }
        else if r > 100 { raw = 4.5 }
        else { raw = 1 + 0.035 * r + r * (r - 60) * (100 - r) * 7e-6 }
        let clamped = max(1.0, min(raw, 4.5))
        let scaled = 1 + (clamped - 1) * (4.0 / 3.5)
        return max(1.0, min(scaled, 5.0))
    }
}
