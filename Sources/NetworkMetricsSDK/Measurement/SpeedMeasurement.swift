import Foundation
import os.log

private let speedLog = OSLog(subsystem: "com.networkmetrics", category: "Speed")

// Downloads a fixed-size chunk and returns bytes received + time elapsed.
// Simple: one URLSession.data(from:) call, no delegate, no race.
private func downloadChunk(url: URL, timeoutSec: Double) async -> (Int64, Double) {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest  = timeoutSec
    config.timeoutIntervalForResource = timeoutSec + 5
    let session = URLSession(configuration: config)
    let start = Date()
    do {
        let (data, _) = try await session.data(from: url)
        let elapsed = Date().timeIntervalSince(start)
        return (Int64(data.count), elapsed)
    } catch {
        return (0, Date().timeIntervalSince(start))
    }
}

internal struct SpeedMeasurement {
    private let downloadDurationMs: Int
    private let uploadDurationMs: Int
    private let threadCount: Int

    // 10 MB chunk — completes in ~1s on typical connection, repeat until deadline
    private static let chunkUrl    = "https://speed.cloudflare.com/__down?bytes=10000000"
    private static let uploadUrl   = "https://speed.cloudflare.com/__up"
    private static let traceUrl    = "https://speed.cloudflare.com/cdn-cgi/trace"

    init(downloadDurationMs: Int = 10000, uploadDurationMs: Int = 8000, threadCount: Int = 3) {
        self.downloadDurationMs = downloadDurationMs
        self.uploadDurationMs   = uploadDurationMs
        self.threadCount        = threadCount
    }

    func measure() async -> SpeedResult? {
        // Run download + loaded latency probes concurrently
        let dlTask = Task.detached { await self.measureDownload() }
        let loadedLatTask = Task.detached { await self.measureLoadedLatency() }

        let dlMbps = await dlTask.value
        os_log("speed: dl=%.2f Mbps", log: speedLog, type: .debug, dlMbps)
        let loadedLatMs = await loadedLatTask.value

        let ulMbps            = await measureUpload()
        let (latMs, jitterMs) = await measureLatencyJitter()
        let (serverName, serverLocation) = await fetchTrace()

        guard dlMbps > 0 else { return nil }

        return SpeedResult(
            downloadMbps: dlMbps,
            uploadMbps: ulMbps,
            latencyMs: latMs,
            jitterMs: jitterMs,
            loadedLatencyMs: loadedLatMs,
            serverName: serverName,
            serverLocation: serverLocation
        )
    }

    // Fires 5 HEAD requests to Cloudflare during the download window and averages RTT.
    private func measureLoadedLatency() async -> Double? {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=0") else { return nil }
        let durationSec = Double(downloadDurationMs) / 1000.0
        let deadline = Date().addingTimeInterval(durationSec * 0.9) // stay within DL window
        var samples: [Double] = []
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 5
        while Date() < deadline && samples.count < 8 {
            let t = Date()
            _ = try? await URLSession.shared.data(for: req)
            let rtt = Date().timeIntervalSince(t) * 1000.0
            if rtt > 0 { samples.append(rtt) }
        }
        guard samples.count >= 2 else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }

    private func measureDownload() async -> Double {
        guard let url = URL(string: Self.chunkUrl) else { return 0 }
        let durationSec = Double(downloadDurationMs) / 1000.0
        let deadline = Date().addingTimeInterval(durationSec)
        let start = Date()

        // Run threadCount parallel loops, each downloading chunks until deadline
        let handles: [Task<Int64, Never>] = (0..<threadCount).map { _ in
            Task.detached {
                var bytes: Int64 = 0
                while Date() < deadline {
                    let remaining = deadline.timeIntervalSinceNow
                    guard remaining > 0.5 else { break }
                    let (b, _) = await downloadChunk(url: url, timeoutSec: min(remaining + 2, durationSec + 5))
                    bytes += b
                }
                return bytes
            }
        }

        var totalBytes: Int64 = 0
        for h in handles { totalBytes += await h.value }

        let elapsed = Date().timeIntervalSince(start)
        os_log("speed: dl %lld bytes in %.2fs", log: speedLog, type: .debug, totalBytes, elapsed)
        guard elapsed > 0, totalBytes > 10000 else { return 0 }
        return Double(totalBytes) * 8.0 / elapsed / 1_000_000.0
    }

    private func measureUpload() async -> Double {
        os_log("speed: upload start", log: speedLog, type: .debug)
        let payload = Data(repeating: 0x41, count: 2_000_000)
        let durationSec = Double(uploadDurationMs) / 1000.0
        let deadline = Date().addingTimeInterval(durationSec)
        let start = Date()

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 10
        sessionConfig.timeoutIntervalForResource = durationSec + 5
        let session = URLSession(configuration: sessionConfig)

        let handles: [Task<Int, Never>] = (0..<threadCount).map { _ in
            Task.detached {
                var bytes = 0
                while Date() < deadline {
                    guard let url = URL(string: Self.uploadUrl) else { break }
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                    do {
                        let (_, resp) = try await session.upload(for: req, from: payload)
                        if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                            bytes += payload.count
                        } else {
                            break
                        }
                    } catch {
                        break
                    }
                }
                return bytes
            }
        }

        var totalBytes = 0
        for h in handles { totalBytes += await h.value }
        session.invalidateAndCancel()

        let elapsed = Date().timeIntervalSince(start)
        os_log("speed: upload %d bytes in %.2fs", log: speedLog, type: .debug, totalBytes, elapsed)
        guard elapsed > 0, totalBytes > 10000 else { return 0 }
        return Double(totalBytes) * 8.0 / elapsed / 1_000_000.0
    }

    // 14 samples: 2 warmup (discarded) + 12 measured. Jitter = standard deviation.
    // Matches Android implementation exactly.
    private func measureLatencyJitter() async -> (Double, Double) {
        let url = URL(string: "https://speed.cloudflare.com/__down?bytes=0")!
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 5

        // Warmup: 2 throwaway requests
        for _ in 0..<2 {
            _ = try? await URLSession.shared.data(for: req)
        }

        var samples: [Double] = []
        for _ in 0..<12 {
            let t = Date()
            _ = try? await URLSession.shared.data(for: req)
            samples.append(Date().timeIntervalSince(t) * 1000.0)
        }
        guard !samples.isEmpty else { return (0, 0) }
        let avg = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.map { pow($0 - avg, 2) }.reduce(0, +) / Double(samples.count)
        let stdDev = variance.squareRoot()
        return (avg, stdDev)
    }

    private func fetchTrace() async -> (String?, String?) {
        guard let url = URL(string: Self.traceUrl),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let text = String(data: data, encoding: .utf8) else { return (nil, nil) }
        var colo: String? = nil
        var loc: String? = nil
        for line in text.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "=")
            if parts.count == 2 {
                switch parts[0] {
                case "colo": colo = parts[1]
                case "loc":  loc  = parts[1]
                default: break
                }
            }
        }
        return (colo, loc)
    }
}
