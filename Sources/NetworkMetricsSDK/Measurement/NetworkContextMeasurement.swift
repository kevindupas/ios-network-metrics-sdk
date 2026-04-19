import Foundation
import Network

internal struct NetworkContextMeasurement {
    private static let traceUrl = "https://1.1.1.1/cdn-cgi/trace"
    private static let cfLocationsUrl = "https://speed.cloudflare.com/locations"

    func measure() async -> NetworkResult {
        let connType  = await detectConnectionType()
        let ipVersion = await detectIpVersion()

        let trace = await fetchCfTrace()
        let userIp      = trace["ip"] ?? ""
        let colo        = trace["colo"] ?? ""
        let countryCode = trace["loc"] ?? ""

        // Fallback chain: ipapi.co first, ipwho.is second. Android parity.
        let extra = await resolveAsnIspCity(ip: userIp)
        let serverCity = await fetchCfServerCity(colo: colo)

        return NetworkResult(
            connectionType: connType,
            ip: userIp.isEmpty ? nil : userIp,
            asn: extra.asn,
            isp: extra.isp,
            city: extra.city,
            country: extra.country,
            countryCode: countryCode.isEmpty ? nil : countryCode,
            cfColo: colo.isEmpty ? nil : colo,
            cfServerCity: serverCity,
            isLocallyServed: nil,
            ipVersion: ipVersion
        )
    }

    private func fetchCfTrace() async -> [String: String] {
        guard let url = URL(string: Self.traceUrl),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let text = String(data: data, encoding: .utf8) else { return [:] }
        var fields: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            guard let idx = line.firstIndex(of: "=") else { continue }
            let k = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
            let v = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            if !k.isEmpty { fields[k] = v }
        }
        return fields
    }

    private struct IpInfo {
        var asn: String?
        var isp: String?
        var city: String?
        var country: String?
    }

    private func resolveAsnIspCity(ip: String) async -> IpInfo {
        var info = IpInfo()

        // 1. ipapi.co
        if let url = URL(string: "https://ipapi.co/\(ip)/json/"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           !(j["asn"] is NSNull), j["asn"] != nil {
            info.asn = (j["asn"] as? String)
            info.isp = (j["org"] as? String)
            info.city = (j["city"] as? String)
            info.country = (j["country_name"] as? String)
            return info
        }

        // 2. ipwho.is fallback
        if let url = URL(string: "https://ipwho.is/\(ip)"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let conn = j["connection"] as? [String: Any] {
                if let asnNum = conn["asn"] as? Int {
                    info.asn = "AS\(asnNum)"
                } else if let asnStr = conn["asn"] as? String {
                    info.asn = "AS\(asnStr)"
                }
                info.isp = conn["org"] as? String
            }
            info.city = j["city"] as? String
            info.country = j["country"] as? String
        }
        return info
    }

    private func fetchCfServerCity(colo: String) async -> String? {
        guard !colo.isEmpty,
              let url = URL(string: Self.cfLocationsUrl),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        for obj in arr {
            if let iata = obj["iata"] as? String, iata == colo {
                return obj["city"] as? String
            }
        }
        return nil
    }

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
                else if has4     { result = "IPv4" }
                else              { result = "unknown" }
                cont.resume(returning: result)
            }
            monitor.start(queue: .global())
        }
    }
}
