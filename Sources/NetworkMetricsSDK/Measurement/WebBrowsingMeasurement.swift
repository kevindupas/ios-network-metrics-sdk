import Foundation

private final class TimingDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    // Phase-only durations (matches Android OkHttp EventListener semantics)
    var dnsMs:  Int64? = nil
    var tcpMs:  Int64? = nil
    var tlsMs:  Int64? = nil
    var ttfbMs: Int64? = nil

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let t = metrics.transactionMetrics.first else { return }

        if let s = t.domainLookupStartDate, let e = t.domainLookupEndDate {
            dnsMs = Int64(e.timeIntervalSince(s) * 1000)
        }
        var tlsPhaseMs: Int64 = 0
        if let s = t.secureConnectionStartDate, let e = t.secureConnectionEndDate {
            tlsPhaseMs = Int64(e.timeIntervalSince(s) * 1000)
            tlsMs = tlsPhaseMs
        }
        if let s = t.connectStartDate, let e = t.connectEndDate {
            // tcp phase = connect total minus TLS handshake (Android parity)
            let totalMs = Int64(e.timeIntervalSince(s) * 1000)
            tcpMs = max(0, totalMs - tlsPhaseMs)
        }
        if let s = t.requestStartDate, let e = t.responseStartDate {
            ttfbMs = Int64(e.timeIntervalSince(s) * 1000)
        }
    }
}

internal struct WebBrowsingMeasurement {
    private let targets: [WebTarget]

    init(targets: [WebTarget]) {
        self.targets = targets
    }

    func measure() async -> [WebBrowsingResult] {
        // Sequential to avoid withTaskGroup Swift runtime heap corruption (swift#75501)
        var results: [WebBrowsingResult] = []
        for target in targets {
            results.append(await probe(target: target))
        }
        return results
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
            // Android parity: success = 2xx OR 3xx (followRedirects=true treats 3xx as ok)
            let success = status.map { (200...399).contains($0) } ?? false

            return WebBrowsingResult(name: target.name, url: target.url,
                                     dnsMs: delegate.dnsMs, tcpMs: delegate.tcpMs,
                                     tlsMs: delegate.tlsMs, ttfbMs: delegate.ttfbMs,
                                     totalMs: totalMs, httpStatus: status,
                                     success: success, error: nil)
        } catch {
            let totalMs = Int64(Date().timeIntervalSince(totalStart) * 1000)
            return WebBrowsingResult(name: target.name, url: target.url,
                                     dnsMs: delegate.dnsMs, tcpMs: delegate.tcpMs,
                                     tlsMs: delegate.tlsMs, ttfbMs: delegate.ttfbMs,
                                     totalMs: totalMs, httpStatus: nil, success: false,
                                     error: String(error.localizedDescription.prefix(120)))
        }
    }
}
