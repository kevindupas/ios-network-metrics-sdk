import Foundation

internal actor RemoteConfigFetcher {
    private static var cachedTargets: [WebTarget]? = nil
    private static var cacheTime: Date? = nil
    private static let ttl: TimeInterval = 3600

    static func fetchWebTargets(url: String, authHeader: String?,
                                 defaults: [WebTarget]) async -> [WebTarget] {
        if let cached = cachedTargets,
           let t = cacheTime, Date().timeIntervalSince(t) < ttl {
            return cached
        }
        guard let reqUrl = URL(string: url) else { return defaults }
        var req = URLRequest(url: reqUrl)
        req.timeoutInterval = 10
        if let auth = authHeader { req.setValue(auth, forHTTPHeaderField: "Authorization") }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["targets"] as? [[String: String]] else { return defaults }
        let targets = arr.compactMap { d -> WebTarget? in
            guard let name = d["name"], let u = d["url"] else { return nil }
            return WebTarget(name: name, url: u)
        }
        cachedTargets = targets.isEmpty ? defaults : targets
        cacheTime = Date()
        return cachedTargets!
    }
}
