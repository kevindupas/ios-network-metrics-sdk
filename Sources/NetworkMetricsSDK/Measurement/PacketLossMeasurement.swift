import Foundation
import Network

internal struct PacketLossMeasurement {
    private let host: String
    private let udpPort: Int
    private let tcpPort: Int

    private let packetCount = 30           // 3G-safe, statistically valid
    private let intervalMs: UInt64 = 50    // 50ms between packets
    private let timeoutSec: Double = 5.0   // 5s per packet — Africa latency
    private let probePayload = "PING"

    init(host: String, udpPort: Int, tcpPort: Int) {
        self.host    = host
        self.udpPort = udpPort
        self.tcpPort = tcpPort
    }

    func measure() async -> UdpResult? {
        guard !host.isEmpty else { return nil }
        if await probeUdp() {
            return await measureUDP()
        }
        return await measureTCP()
    }

    private func probeUdp() async -> Bool {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(udpPort)),
            using: .udp
        )
        return await withCheckedContinuation { cont in
            let q = DispatchQueue(label: "nm.udp.probe")
            var settled = false
            func resolve(_ ok: Bool) {
                guard !settled else { return }
                settled = true
                connection.cancel()
                cont.resume(returning: ok)
            }
            connection.stateUpdateHandler = { state in
                q.async {
                    switch state {
                    case .ready:
                        let payload = self.probePayload.data(using: .utf8)!
                        connection.send(content: payload, completion: .contentProcessed { _ in })
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 64) { data, _, _, _ in
                            resolve(data != nil)
                        }
                        q.asyncAfter(deadline: .now() + 5) { resolve(false) }
                    case .failed, .cancelled:
                        resolve(false)
                    default:
                        break
                    }
                }
            }
            connection.start(queue: q)
        }
    }

    private func measureUDP() async -> UdpResult {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(udpPort)),
            using: .udp
        )
        return await withCheckedContinuation { cont in
            let q = DispatchQueue(label: "nm.udp")
            var sent = 0
            var received = 0
            var resumed = false

            func finish() {
                guard !resumed else { return }
                resumed = true
                connection.cancel()
                let loss = sent > 0 ? Double(sent - received) / Double(sent) * 100.0 : 100.0
                cont.resume(returning: UdpResult(sent: sent, received: received, lossPercent: loss, method: "udp"))
            }

            connection.stateUpdateHandler = { state in
                q.async {
                    switch state {
                    case .ready:
                        Task.detached {
                            for seq in 0..<self.packetCount {
                                let payload = "SEQ:\(seq)".data(using: .utf8)!
                                connection.send(content: payload, completion: .contentProcessed { err in
                                    q.async {
                                        if err == nil { sent += 1 }
                                    }
                                })
                                connection.receive(minimumIncompleteLength: 1, maximumLength: 64) { data, _, _, _ in
                                    q.async {
                                        if data != nil { received += 1 }
                                    }
                                }
                                try? await Task.sleep(nanoseconds: self.intervalMs * 1_000_000)
                            }
                            // Wait up to 5s for late packets after last send
                            try? await Task.sleep(nanoseconds: UInt64(self.timeoutSec * 1_000_000_000))
                            q.async { finish() }
                        }
                    case .failed, .cancelled:
                        finish()
                    default:
                        break
                    }
                }
            }
            connection.start(queue: q)
        }
    }

    private func measureTCP() async -> UdpResult {
        guard let url = URL(string: "http://\(host):\(tcpPort)/ping") else {
            return UdpResult(sent: 0, received: 0, lossPercent: 100, method: "tcp")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeoutSec
        var sent = 0
        var received = 0
        for _ in 0..<packetCount {
            sent += 1
            if let _ = try? await URLSession.shared.data(for: req) { received += 1 }
            try? await Task.sleep(nanoseconds: intervalMs * 1_000_000)
        }
        let loss = sent > 0 ? Double(sent - received) / Double(sent) * 100.0 : 100.0
        return UdpResult(sent: sent, received: received, lossPercent: loss, method: "tcp")
    }
}
