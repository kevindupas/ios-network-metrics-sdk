import Foundation

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
        r = max(0, min(r, 100))
        if r < 0 { return 1.0 }
        return 1 + 0.035 * r + r * (r - 60) * (100 - r) * 7e-6
    }
}
