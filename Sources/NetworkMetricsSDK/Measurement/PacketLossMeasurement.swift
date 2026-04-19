import Foundation
import Network

internal struct PacketLossMeasurement {
    private let host: String
    private let udpPort: Int
    private let tcpPort: Int
    private let packetCount = 100

    init(host: String, udpPort: Int, tcpPort: Int) {
        self.host    = host
        self.udpPort = udpPort
        self.tcpPort = tcpPort
    }

    func measure() async -> UdpResult {
        let result = await measureUDP()
        if let r = result { return r }
        return await measureTCP()
    }

    private func measureUDP() async -> UdpResult? {
        guard !host.isEmpty else { return nil }
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
                cont.resume(returning: UdpResult(sent: sent, received: received, lossPercent: loss, method: "UDP"))
            }

            connection.stateUpdateHandler = { state in
                q.async {
                    switch state {
                    case .ready:
                        for i in 0..<self.packetCount {
                            let payload = "PING\(i)".data(using: .utf8)!
                            connection.send(content: payload, completion: .contentProcessed { err in
                                q.async {
                                    if err == nil { sent += 1 }
                                }
                            })
                            connection.receive(minimumIncompleteLength: 1, maximumLength: 64) { data, _, _, _ in
                                q.async {
                                    if data != nil { received += 1 }
                                    if received >= self.packetCount { finish() }
                                }
                            }
                        }
                        q.asyncAfter(deadline: .now() + 5) { finish() }
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
        guard !host.isEmpty, let url = URL(string: "http://\(host):\(tcpPort)/ping") else {
            return UdpResult(sent: 0, received: 0, lossPercent: 100, method: "TCP")
        }
        var received = 0
        for _ in 0..<packetCount {
            if let _ = try? await URLSession.shared.data(from: url) { received += 1 }
        }
        let loss = Double(packetCount - received) / Double(packetCount) * 100.0
        return UdpResult(sent: packetCount, received: received, lossPercent: loss, method: "TCP")
    }
}
