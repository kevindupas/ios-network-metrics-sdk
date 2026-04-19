import Foundation

public struct NetworkMetricsRecord: Codable {
    public let testId: String
    public let deviceId: String
    public let timestamp: String
    public let sdkVersion: String
    public let speed: SpeedResult?
    public let udpPacketLoss: UdpResult?
    public let streaming: StreamingResult?
    public let socialLatency: [SocialLatencyResult]
    public let radio: RadioResult?
    public let network: NetworkResult
    public let geo: GeoResult?
    public let device: DeviceResult
    public let scores: QualityScores?
    public let mos: Double?
    public let dns: DnsResult?
    public let webBrowsing: [WebBrowsingResult]
    public let neighboringCells: [NeighboringCellResult]
}

public struct RadioResult: Codable {
    public let rsrp: Int?
    public let rsrq: Int?
    public let sinr: Int?
    public let rssi: Int?
    public let cqi: Int?
    public let ci: Int64?
    public let pci: Int?
    public let tac: Int?
    public let lac: Int?
    public let earfcn: Int?
    public let bandwidth: Int?
    public let psc: Int?
    public let isNrAvailable: Bool
    public let isVoLteAvailable: Bool
    public let isVoNrAvailable: Bool
    public let isRoaming: Bool
    public let nrMode: String?
    public let networkGeneration: String
    public let signalStrengthLevel: String
    public let technology: String
}

public struct NeighboringCellResult: Codable {
    public let type: String
    public let pci: Int?
    public let ci: Int64?
    public let rsrp: Int?
    public let rsrq: Int?
    public let rssi: Int?
    public let tac: Int?
    public let lac: Int?
    public let earfcn: Int?
    public let isRegistered: Bool
}

public struct SpeedResult: Codable {
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let latencyMs: Double
    public let jitterMs: Double
    public let loadedLatencyMs: Double?
    public let serverName: String?
    public let serverLocation: String?
}

public struct UdpResult: Codable {
    public let sent: Int
    public let received: Int
    public let lossPercent: Double
    public let method: String
}

public struct StreamingResult: Codable {
    public let startTimeMs: Int64?
    public let rebufferCount: Int
    public let rebufferDurationMs: Int64
    public let avgBitrateKbps: Int?
    public let durationMeasuredMs: Int64
    public let bytesDownloaded: Int64
    public let error: String?
}

public struct SocialLatencyResult: Codable {
    public let service: String
    public let ttfbMs: Int64?
    public let reachable: Bool
}

public struct DnsResult: Codable {
    public let resolveMs: Int64
    public let host: String
    public let resolvedIps: [String]
    public let success: Bool
}

public struct WebBrowsingResult: Codable {
    public let name: String
    public let url: String
    public let dnsMs: Int64?
    public let tcpMs: Int64?
    public let tlsMs: Int64?
    public let ttfbMs: Int64?
    public let totalMs: Int64?
    public let httpStatus: Int?
    public let success: Bool
    public let error: String?
}

public struct NetworkResult: Codable {
    public let connectionType: String
    public let ip: String?
    public let asn: String?
    public let isp: String?
    public let city: String?
    public let country: String?
    public let countryCode: String?
    public let cfColo: String?
    public let cfServerCity: String?
    public let isLocallyServed: Bool?
    public let ipVersion: String?
}

public struct GeoResult: Codable {
    public let lat: Double
    public let lon: Double
    public let accuracy: Double
    public let altitude: Double?
    public let speed: Double?
    public let bearing: Double?
    public let provider: String?
}

public struct DeviceResult: Codable {
    public let manufacturer: String
    public let model: String
    public let osVersion: String
    public let sdkInt: Int
    public let simOperatorName: String?
    public let mcc: String?
    public let mnc: String?
    public let batteryLevel: Int?
    public let isCharging: Bool?
    public let ramUsedMb: Int?
    public let cpuLoadPercent: Double?
    public let thermalStatus: String?
}

public struct QualityScores: Codable {
    public let streaming: ScoreEntry?
    public let gaming: ScoreEntry?
    public let rtc: ScoreEntry?
}

public struct ScoreEntry: Codable {
    public let score: Int
    public let label: String
}
