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
            var sent = 0
            var received = 0
            var done = false

            connection.stateUpdateHandler = { state in
                guard case .ready = state else { return }
                for i in 0..<self.packetCount {
                    let payload = "PING\(i)".data(using: .utf8)!
                    connection.send(content: payload, completion: .contentProcessed { err in
                        if err == nil { sent += 1 }
                    })
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 64) { data, _, _, _ in
                        if data != nil { received += 1 }
                        if received + (self.packetCount - sent) >= self.packetCount && !done {
                            done = true
                            connection.cancel()
                            let loss = sent > 0 ? Double(sent - received) / Double(sent) * 100.0 : 100.0
                            cont.resume(returning: UdpResult(sent: sent, received: received, lossPercent: loss, method: "UDP"))
                        }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if !done {
                        done = true
                        connection.cancel()
                        let loss = sent > 0 ? Double(sent - received) / Double(sent) * 100.0 : 100.0
                        cont.resume(returning: UdpResult(sent: sent, received: received, lossPercent: loss, method: "UDP"))
                    }
                }
            }
            connection.start(queue: .global())
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
