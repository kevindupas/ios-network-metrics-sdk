import Foundation

internal struct SocialLatencyMeasurement {
    private static let targets: [(String, String)] = [
        ("WhatsApp",   "https://web.whatsapp.com"),
        ("Facebook",   "https://www.facebook.com"),
        ("YouTube",    "https://www.youtube.com"),
        ("Twitter",    "https://www.twitter.com"),
        ("Instagram",  "https://www.instagram.com"),
        ("TikTok",     "https://www.tiktok.com"),
    ]

    func measure() async -> [SocialLatencyResult] {
        await withTaskGroup(of: SocialLatencyResult.self) { group in
            for (name, urlStr) in Self.targets {
                group.addTask { await probe(name: name, urlStr: urlStr) }
            }
            var results: [SocialLatencyResult] = []
            for await r in group { results.append(r) }
            return results
        }
    }

    private func probe(name: String, urlStr: String) async -> SocialLatencyResult {
        guard let url = URL(string: urlStr) else {
            return SocialLatencyResult(service: name, ttfbMs: nil, reachable: false)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 10
        let start = Date()
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let elapsed = Int64(Date().timeIntervalSince(start) * 1000)
            let ok = (resp as? HTTPURLResponse).map { $0.statusCode < 500 } ?? false
            return SocialLatencyResult(service: name, ttfbMs: elapsed, reachable: ok)
        } catch {
            return SocialLatencyResult(service: name, ttfbMs: nil, reachable: false)
        }
    }
}
