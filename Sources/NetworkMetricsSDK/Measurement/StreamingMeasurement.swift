import Foundation

internal struct StreamingMeasurement {
    private static let hlsUrl = "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
    private let durationMs: Int64 = 15_000

    func measure() async -> StreamingResult {
        guard let url = URL(string: Self.hlsUrl) else {
            return StreamingResult(startTimeMs: nil, rebufferCount: 0,
                                   rebufferDurationMs: 0, avgBitrateKbps: nil,
                                   durationMeasuredMs: 0, bytesDownloaded: 0,
                                   error: "Invalid URL")
        }

        let start = Date()
        var bytesDownloaded: Int64 = 0
        var error: String? = nil

        do {
            let manifest = try await fetchManifest(url: url)
            let segmentUrls = parseSegments(manifest: manifest, base: url)
            let deadline = Date().addingTimeInterval(Double(durationMs) / 1000.0)

            for segUrl in segmentUrls {
                guard Date() < deadline else { break }
                if let (data, _) = try? await URLSession.shared.data(from: segUrl) {
                    bytesDownloaded += Int64(data.count)
                }
            }
        } catch let e {
            error = e.localizedDescription
        }

        let elapsed = Int64(Date().timeIntervalSince(start) * 1000)
        let startTimeMs = Int64(start.timeIntervalSince1970 * 1000)
        let avgBitrate = elapsed > 0 ? Int(Double(bytesDownloaded * 8) / Double(elapsed)) : nil

        return StreamingResult(
            startTimeMs: startTimeMs,
            rebufferCount: 0,
            rebufferDurationMs: 0,
            avgBitrateKbps: avgBitrate,
            durationMeasuredMs: elapsed,
            bytesDownloaded: bytesDownloaded,
            error: error
        )
    }

    private func fetchManifest(url: URL) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: url)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parseSegments(manifest: String, base: URL) -> [URL] {
        manifest.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("#") && !$0.isEmpty }
            .compactMap { line -> URL? in
                if line.hasPrefix("http") { return URL(string: line) }
                return URL(string: line, relativeTo: base)?.absoluteURL
            }
    }
}
