import Foundation

public struct WebTarget {
    public let name: String
    public let url: String
    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

public struct NetworkMetricsConfig {
    public let backendUrl: String
    public let authHeader: String?
    public let intervalMinutes: Int
    public let enableSpeed: Bool
    public let enablePacketLoss: Bool
    public let enableStreaming: Bool
    public let enableSocialLatency: Bool
    public let enableDns: Bool
    public let enableWebBrowsing: Bool
    public let speedDownloadDurationMs: Int
    public let speedUploadDurationMs: Int
    public let speedThreadCount: Int
    public let udpHost: String
    public let udpPort: Int
    public let tcpPort: Int
    public let webTargets: [WebTarget]
    public let remoteConfigUrl: String?

    public static let defaultWebTargets: [WebTarget] = [
        WebTarget(name: "Google", url: "https://www.google.com"),
        WebTarget(name: "YouTube", url: "https://www.youtube.com"),
        WebTarget(name: "WhatsApp", url: "https://web.whatsapp.com"),
        WebTarget(name: "Facebook", url: "https://www.facebook.com"),
        WebTarget(name: "Twitter", url: "https://www.twitter.com"),
    ]

    public init(
        backendUrl: String,
        authHeader: String? = nil,
        intervalMinutes: Int = 15,
        enableSpeed: Bool = true,
        enablePacketLoss: Bool = true,
        enableStreaming: Bool = true,
        enableSocialLatency: Bool = true,
        enableDns: Bool = true,
        enableWebBrowsing: Bool = true,
        speedDownloadDurationMs: Int = 10000,
        speedUploadDurationMs: Int = 8000,
        speedThreadCount: Int = 3,
        udpHost: String = "",
        udpPort: Int = 5005,
        tcpPort: Int = 5006,
        webTargets: [WebTarget] = NetworkMetricsConfig.defaultWebTargets,
        remoteConfigUrl: String? = nil
    ) {
        self.backendUrl = backendUrl
        self.authHeader = authHeader
        self.intervalMinutes = intervalMinutes
        self.enableSpeed = enableSpeed
        self.enablePacketLoss = enablePacketLoss
        self.enableStreaming = enableStreaming
        self.enableSocialLatency = enableSocialLatency
        self.enableDns = enableDns
        self.enableWebBrowsing = enableWebBrowsing
        self.speedDownloadDurationMs = speedDownloadDurationMs
        self.speedUploadDurationMs = speedUploadDurationMs
        self.speedThreadCount = speedThreadCount
        self.udpHost = udpHost
        self.udpPort = udpPort
        self.tcpPort = tcpPort
        self.webTargets = webTargets
        self.remoteConfigUrl = remoteConfigUrl
    }
}
