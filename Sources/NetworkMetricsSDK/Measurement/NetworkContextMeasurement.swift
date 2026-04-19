import Foundation
import Network

internal struct NetworkContextMeasurement {
    private static let traceUrl = "https://speed.cloudflare.com/cdn-cgi/trace"

    func measure() async -> NetworkResult {
        let connType = detectConnectionType()
        let ipVersion = detectIpVersion()

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

        let colo       = fields["colo"]
        let loc        = fields["loc"]
        let ip         = fields["ip"]
        let isLocal    = colo.flatMap { c -> Bool? in loc.map { l in c == l } }

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

    private func detectConnectionType() -> String {
        let monitor = NWPathMonitor()
        var type = "unknown"
        let sem = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { path in
            if path.usesInterfaceType(.wifi)      { type = "WiFi" }
            else if path.usesInterfaceType(.cellular) { type = "cellular" }
            else if path.status == .satisfied     { type = "other" }
            else                                   { type = "none" }
            sem.signal()
        }
        monitor.start(queue: .global())
        sem.wait()
        monitor.cancel()
        return type
    }

    private func detectIpVersion() -> String {
        let monitor4 = NWPathMonitor(requiredInterfaceType: .wifi)
        var has4 = false, has6 = false
        let g = DispatchGroup()
        g.enter()
        monitor4.pathUpdateHandler = { path in
            has4 = path.supportsIPv4
            has6 = path.supportsIPv6
            g.leave()
        }
        monitor4.start(queue: .global())
        g.wait()
        monitor4.cancel()
        if has4 && has6 { return "dual" }
        if has6          { return "IPv6" }
        return "IPv4"
    }
}
