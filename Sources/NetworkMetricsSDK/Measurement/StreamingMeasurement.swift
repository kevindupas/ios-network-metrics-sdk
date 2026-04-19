import Foundation

internal struct StreamingMeasurement {
    private static let defaultHlsUrl = "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
    private let durationMs: Int64 = 20_000
    private let hlsUrl: String

    init(streamingUrl: String? = nil) {
        self.hlsUrl = streamingUrl ?? Self.defaultHlsUrl
    }

    func measure() async -> StreamingResult {
        guard let masterUrl = URL(string: hlsUrl) else {
            return StreamingResult(startTimeMs: nil, rebufferCount: 0,
                                   rebufferDurationMs: 0, avgBitrateKbps: nil,
                                   durationMeasuredMs: 0, bytesDownloaded: 0,
                                   error: "Invalid URL")
        }

        let manifestStart = Date()

        // 1. Fetch master manifest
        guard let manifest = try? await fetchText(url: masterUrl) else {
            return StreamingResult(startTimeMs: nil, rebufferCount: 0,
                                   rebufferDurationMs: 0, avgBitrateKbps: nil,
                                   durationMeasuredMs: 0, bytesDownloaded: 0,
                                   error: "manifest fetch failed")
        }

        // 2. Find lowest-bitrate sub-playlist + extract segment URLs
        let segmentUrls = await parseSegmentUrls(manifest: manifest, masterUrl: masterUrl)
        if segmentUrls.isEmpty {
            return StreamingResult(startTimeMs: nil, rebufferCount: 0,
                                   rebufferDurationMs: 0, avgBitrateKbps: nil,
                                   durationMeasuredMs: 0, bytesDownloaded: 0,
                                   error: "no segments found")
        }

        let firstByteMs = Int64(Date().timeIntervalSince(manifestStart) * 1000)
        let deadline = Date().addingTimeInterval(Double(durationMs) / 1000.0)

        var totalBytes: Int64 = 0
        var rebufferCount = 0
        var rebufferDurationMs: Int64 = 0
        var lastSegmentEnd = Date()

        for segUrl in segmentUrls {
            if Date() > deadline { break }
            let segStart = Date()
            if let (data, _) = try? await URLSession.shared.data(from: segUrl) {
                totalBytes += Int64(data.count)
                // Gap between expected segment end and actual = rebuffer
                let gapMs = Int64(segStart.timeIntervalSince(lastSegmentEnd) * 1000)
                if gapMs > 500 {
                    rebufferCount += 1
                    rebufferDurationMs += gapMs
                }
                lastSegmentEnd = Date()
            } else {
                rebufferCount += 1
                rebufferDurationMs += 1000
            }
        }

        let elapsed = Int64(Date().timeIntervalSince(manifestStart) * 1000)
        let avgBitrateKbps = elapsed > 0 ? Int(totalBytes * 8 / elapsed) : nil

        return StreamingResult(
            startTimeMs: firstByteMs,
            rebufferCount: rebufferCount,
            rebufferDurationMs: rebufferDurationMs,
            avgBitrateKbps: avgBitrateKbps,
            durationMeasuredMs: elapsed,
            bytesDownloaded: totalBytes,
            error: nil
        )
    }

    private func fetchText(url: URL) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: url)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Parses master HLS manifest, picks lowest BANDWIDTH variant, fetches sub-playlist,
    /// returns up to 10 resolved segment URLs.
    private func parseSegmentUrls(manifest: String, masterUrl: URL) async -> [URL] {
        let baseUrl = masterUrl.deletingLastPathComponent()
        let lines = manifest.components(separatedBy: "\n")

        // Find lowest-BANDWIDTH STREAM-INF
        var lowestBandwidth = Int64.max
        var playlistLine: String? = nil
        let bwRegex = try? NSRegularExpression(pattern: #"BANDWIDTH=(\d+)"#)
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("#EXT-X-STREAM-INF"),
               i + 1 < lines.count,
               !lines[i + 1].hasPrefix("#") {
                let ns = line as NSString
                let bw: Int64 = {
                    guard let m = bwRegex?.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                          m.numberOfRanges >= 2 else { return Int64.max }
                    return Int64(ns.substring(with: m.range(at: 1))) ?? Int64.max
                }()
                if bw < lowestBandwidth {
                    lowestBandwidth = bw
                    playlistLine = lines[i + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            i += 1
        }

        guard let pl = playlistLine else { return [] }
        let subPlaylistUrl: URL
        if pl.hasPrefix("http"), let u = URL(string: pl) {
            subPlaylistUrl = u
        } else if let u = URL(string: pl, relativeTo: baseUrl)?.absoluteURL {
            subPlaylistUrl = u
        } else {
            return []
        }

        guard let subManifest = try? await fetchText(url: subPlaylistUrl) else { return [] }
        let segBase = subPlaylistUrl.deletingLastPathComponent()

        return subManifest.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .prefix(10)
            .compactMap { line -> URL? in
                if line.hasPrefix("http") { return URL(string: line) }
                return URL(string: line, relativeTo: segBase)?.absoluteURL
            }
    }
}
