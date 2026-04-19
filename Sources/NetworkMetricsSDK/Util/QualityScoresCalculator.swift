import Foundation

internal enum QualityScoresCalculator {
    static func calculate(downloadMbps: Double, latencyMs: Double,
                          jitterMs: Double, lossPercent: Double) -> QualityScores {
        return QualityScores(
            streaming: streamingScore(downloadMbps: downloadMbps),
            gaming:    gamingScore(latencyMs: latencyMs, jitterMs: jitterMs, lossPercent: lossPercent),
            rtc:       rtcScore(latencyMs: latencyMs, jitterMs: jitterMs, lossPercent: lossPercent)
        )
    }

    private static func streamingScore(downloadMbps: Double) -> ScoreEntry {
        switch downloadMbps {
        case 25...:  return ScoreEntry(score: 5, label: "Excellent")
        case 10..<25: return ScoreEntry(score: 4, label: "Good")
        case 5..<10:  return ScoreEntry(score: 3, label: "Average")
        case 2.5..<5: return ScoreEntry(score: 2, label: "Poor")
        default:      return ScoreEntry(score: 1, label: "Bad")
        }
    }

    private static func gamingScore(latencyMs: Double, jitterMs: Double, lossPercent: Double) -> ScoreEntry {
        let score: Int
        if latencyMs < 20 && jitterMs < 5 && lossPercent < 0.5 { score = 5 }
        else if latencyMs < 50 && jitterMs < 15 && lossPercent < 1 { score = 4 }
        else if latencyMs < 100 && jitterMs < 30 && lossPercent < 2 { score = 3 }
        else if latencyMs < 150 { score = 2 }
        else { score = 1 }
        let labels = ["", "Bad", "Poor", "Average", "Good", "Excellent"]
        return ScoreEntry(score: score, label: labels[score])
    }

    private static func rtcScore(latencyMs: Double, jitterMs: Double, lossPercent: Double) -> ScoreEntry {
        let score: Int
        if latencyMs < 50 && jitterMs < 10 && lossPercent < 1 { score = 5 }
        else if latencyMs < 100 && jitterMs < 20 && lossPercent < 2 { score = 4 }
        else if latencyMs < 150 && jitterMs < 40 && lossPercent < 5 { score = 3 }
        else if latencyMs < 300 { score = 2 }
        else { score = 1 }
        let labels = ["", "Bad", "Poor", "Average", "Good", "Excellent"]
        return ScoreEntry(score: score, label: labels[score])
    }
}
