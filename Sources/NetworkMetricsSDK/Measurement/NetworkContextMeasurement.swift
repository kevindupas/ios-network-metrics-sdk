import Foundation
import Network

internal struct NetworkContextMeasurement {
    private static let traceUrl = "https://speed.cloudflare.com/cdn-cgi/trace"

    func measure() async -> NetworkResult {
        let connType = await detectConnectionType()
        let ipVersion = await detectIpVersion()

        guard let url = URL(string: Self.traceUrl),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let text = String(data: data, encoding: .utf8) else {
            return NetworkResult(connectionType: connType, ip: nil, asn: nil, isp: nil,
                                 city: nil, country: nil, countryCode: nil,
                                 cfColo: nil, cfServerCity: nil,
                                 isLocallyServed: nil, ipVersion: ipVersion)
        }

        var fields: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "=")
            if parts.count == 2 { fields[parts[0]] = parts[1] }
        }

        let colo    = fields["colo"]
        let loc     = fields["loc"]
        let ip      = fields["ip"]
        let isLocal = colo.flatMap { c -> Bool? in loc.map { l in c == l } }

        return NetworkResult(
            connectionType: connType,
            ip: ip,
            asn: fields["asn"],
            isp: fields["org"],
            city: nil,
            country: nil,
            countryCode: loc,
            cfColo: colo,
            cfServerCity: nil,
            isLocallyServed: isLocal,
            ipVersion: ipVersion
        )
    }

    // NWPathMonitor with DispatchSemaphore.wait() is forbidden inside Swift concurrency
    // (blocks the cooperative thread pool). Use async continuation instead.
    private func detectConnectionType() async -> String {
        await withCheckedContinuation { cont in
            let monitor = NWPathMonitor()
            var settled = false
            monitor.pathUpdateHandler = { path in
                guard !settled else { return }
                settled = true
                monitor.cancel()
                let type: String
                if path.usesInterfaceType(.wifi)         { type = "WiFi" }
                else if path.usesInterfaceType(.cellular) { type = "cellular" }
                else if path.status == .satisfied         { type = "other" }
                else                                       { type = "none" }
                cont.resume(returning: type)
            }
            monitor.start(queue: .global())
        }
    }

    private func detectIpVersion() async -> String {
        await withCheckedContinuation { cont in
            let monitor = NWPathMonitor()
            var settled = false
            monitor.pathUpdateHandler = { path in
                guard !settled else { return }
                settled = true
                monitor.cancel()
                let has4 = path.supportsIPv4
                let has6 = path.supportsIPv6
                let result: String
                if has4 && has6 { result = "dual" }
                else if has6     { result = "IPv6" }
                else              { result = "IPv4" }
                cont.resume(returning: result)
            }
            monitor.start(queue: .global())
        }
    }
}
