import Foundation

internal struct DnsMeasurement {
    private let host: String

    init(host: String = "www.google.com") {
        self.host = host
    }

    func measure() async -> DnsResult {
        return await withCheckedContinuation { cont in
            let start = Date()
            var hints = addrinfo()
            hints.ai_family   = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM
            var res: UnsafeMutablePointer<addrinfo>? = nil
            let err = getaddrinfo(host, nil, &hints, &res)
            let elapsed = Int64(Date().timeIntervalSince(start) * 1000)

            guard err == 0, let first = res else {
                cont.resume(returning: DnsResult(resolveMs: elapsed, host: host, resolvedIps: [], success: false))
                return
            }

            var ips: [String] = []
            var ptr = first
            while true {
                var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                if ptr.pointee.ai_family == AF_INET {
                    var addr = (ptr.pointee.ai_addr.pointee as sockaddr)
                    withUnsafePointer(to: &addr) { p in
                        p.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { p4 in
                            var sin = p4.pointee.sin_addr
                            inet_ntop(AF_INET, &sin, &buf, socklen_t(INET_ADDRSTRLEN))
                        }
                    }
                } else if ptr.pointee.ai_family == AF_INET6 {
                    var addr = (ptr.pointee.ai_addr.pointee as sockaddr)
                    withUnsafePointer(to: &addr) { p in
                        p.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { p6 in
                            var sin6 = p6.pointee.sin6_addr
                            inet_ntop(AF_INET6, &sin6, &buf, socklen_t(INET6_ADDRSTRLEN))
                        }
                    }
                }
                let ip = String(cString: buf)
                if !ip.isEmpty && !ips.contains(ip) { ips.append(ip) }
                guard let next = ptr.pointee.ai_next else { break }
                ptr = next
            }
            freeaddrinfo(first)

            cont.resume(returning: DnsResult(resolveMs: elapsed, host: host, resolvedIps: ips, success: true))
        }
    }
}
