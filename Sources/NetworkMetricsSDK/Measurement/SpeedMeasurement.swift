import Foundation

internal struct SpeedMeasurement {
    private let downloadDurationMs: Int
    private let uploadDurationMs: Int
    private let threadCount: Int

    private static let downloadUrl = "https://speed.cloudflare.com/__down?bytes=100000000"
    private static let uploadUrl   = "https://speed.cloudflare.com/__up"
    private static let traceUrl    = "https://speed.cloudflare.com/cdn-cgi/trace"

    init(downloadDurationMs: Int = 10000, uploadDurationMs: Int = 8000, threadCount: Int = 3) {
        self.downloadDurationMs = downloadDurationMs
        self.uploadDurationMs   = uploadDurationMs
        self.threadCount        = threadCount
    }

    func measure() async -> SpeedResult? {
        async let dl = measureDownload()
        async let ul = measureUpload()
        async let latJitter = measureLatencyJitter()
        async let trace = fetchTrace()

        let dlMbps = await dl
        let ulMbps = await ul
        let (latMs, jitterMs) = await latJitter
        let (serverName, serverLocation) = await trace

        guard dlMbps > 0 else { return nil }

        return SpeedResult(
            downloadMbps: dlMbps,
            uploadMbps: ulMbps,
            latencyMs: latMs,
            jitterMs: jitterMs,
            loadedLatencyMs: nil,
            serverName: serverName,
            serverLocation: serverLocation
        )
    }

    private func measureDownload() async -> Double {
        var totalBytes = 0
        let deadline = Date().addingTimeInterval(Double(downloadDurationMs) / 1000.0)
        let start = Date()

        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<threadCount {
                group.addTask {
                    var bytes = 0
                    while Date() < deadline {
                        guard let url = URL(string: Self.downloadUrl) else { break }
                        guard let (data, _) = try? await URLSession.shared.data(from: url) else { break }
                        bytes += data.count
                    }
                    return bytes
                }
            }
            for await b in group { totalBytes += b }
        }

        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return 0 }
        return Double(totalBytes) * 8.0 / elapsed / 1_000_000.0
    }

    private func measureUpload() async -> Double {
        let payload = Data(repeating: 0x41, count: 1_000_000)
        var totalBytes = 0
        let deadline = Date().addingTimeInterval(Double(uploadDurationMs) / 1000.0)
        let start = Date()

        while Date() < deadline {
            guard let url = URL(string: Self.uploadUrl) else { break }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody = payload
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            guard let (_, _) = try? await URLSession.shared.data(for: req) else { break }
            totalBytes += payload.count
        }

        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return 0 }
        return Double(totalBytes) * 8.0 / elapsed / 1_000_000.0
    }

    private func measureLatencyJitter() async -> (Double, Double) {
        let url = URL(string: "https://speed.cloudflare.com/__down?bytes=0")!
        var samples: [Double] = []
        for _ in 0..<10 {
            let t = Date()
            _ = try? await URLSession.shared.data(from: url)
            samples.append(Date().timeIntervalSince(t) * 1000.0)
        }
        guard !samples.isEmpty else { return (0, 0) }
        let avg = samples.reduce(0, +) / Double(samples.count)
        let jitter = samples.map { abs($0 - avg) }.reduce(0, +) / Double(samples.count)
        return (avg, jitter)
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
