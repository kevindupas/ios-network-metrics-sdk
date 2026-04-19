import Foundation

private final class TimingDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    var dnsEnd:  Date? = nil
    var tcpEnd:  Date? = nil
    var tlsEnd:  Date? = nil
    var ttfb:    Date? = nil
    var start:   Date = Date()

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let t = metrics.transactionMetrics.first else { return }
        start   = t.fetchStartDate ?? start
        dnsEnd  = t.domainLookupEndDate
        tcpEnd  = t.connectEndDate
        tlsEnd  = t.secureConnectionEndDate
        ttfb    = t.responseStartDate
    }
}

internal struct WebBrowsingMeasurement {
    private let targets: [WebTarget]

    init(targets: [WebTarget]) {
        self.targets = targets
    }

    func measure() async -> [WebBrowsingResult] {
        await withTaskGroup(of: WebBrowsingResult.self) { group in
            for target in targets {
                group.addTask { await probe(target: target) }
            }
            var results: [WebBrowsingResult] = []
            for await r in group { results.append(r) }
            return results
        }
    }

    private func probe(target: WebTarget) async -> WebBrowsingResult {
        guard let url = URL(string: target.url) else {
            return WebBrowsingResult(name: target.name, url: target.url,
                                     dnsMs: nil, tcpMs: nil, tlsMs: nil, ttfbMs: nil,
                                     totalMs: nil, httpStatus: nil, success: false,
                                     error: "Invalid URL")
        }

        let delegate = TimingDelegate()
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 15

        let totalStart = Date()
        do {
            let (_, resp) = try await session.data(for: req)
            let totalMs = Int64(Date().timeIntervalSince(totalStart) * 1000)
            let status = (resp as? HTTPURLResponse)?.statusCode

            let dnsMs  = delegate.dnsEnd.map  { Int64($0.timeIntervalSince(delegate.start) * 1000) }
            let tcpMs  = delegate.tcpEnd.map  { Int64($0.timeIntervalSince(delegate.start) * 1000) }
            let tlsMs  = delegate.tlsEnd.map  { Int64($0.timeIntervalSince(delegate.start) * 1000) }
            let ttfbMs = delegate.ttfb.map    { Int64($0.timeIntervalSince(delegate.start) * 1000) }

            return WebBrowsingResult(name: target.name, url: target.url,
                                     dnsMs: dnsMs, tcpMs: tcpMs, tlsMs: tlsMs, ttfbMs: ttfbMs,
                                     totalMs: totalMs, httpStatus: status, success: true, error: nil)
        } catch {
            return WebBrowsingResult(name: target.name, url: target.url,
                                     dnsMs: nil, tcpMs: nil, tlsMs: nil, ttfbMs: nil,
                                     totalMs: nil, httpStatus: nil, success: false,
                                     error: error.localizedDescription)
        }
    }
}
