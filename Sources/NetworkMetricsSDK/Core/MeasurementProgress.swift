import Foundation

public enum MeasurementPhase: String {
    case speedDownloadProgress = "SPEED_DOWNLOAD_PROGRESS"
    case speedUploadProgress   = "SPEED_UPLOAD_PROGRESS"
    case speed                 = "SPEED"
    case packetLoss            = "PACKET_LOSS"
    case streaming             = "STREAMING"
    case socialLatency         = "SOCIAL_LATENCY"
    case dns                   = "DNS"
    case webBrowsing           = "WEB_BROWSING"
    case radio                 = "RADIO"
    case network               = "NETWORK"
    case device                = "DEVICE"
    case geo                   = "GEO"
    case complete              = "COMPLETE"
}

public struct MeasurementProgress {
    public let phase: MeasurementPhase
    public let result: Any?
}

public typealias ProgressCallback = @Sendable (MeasurementProgress) -> Void
