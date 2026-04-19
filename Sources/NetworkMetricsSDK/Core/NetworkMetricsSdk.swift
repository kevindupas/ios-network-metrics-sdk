import Foundation
import BackgroundTasks
import UIKit

private let prefsKey   = "nm_last_result"
private let prefsKeyAt = "nm_last_result_at"
private let bgTaskId   = "com.networkmetrics.refresh"
private let sdkVersion = "1.0.5"

public final class NetworkMetricsSdk {
    public static let shared = NetworkMetricsSdk()
    private var config: NetworkMetricsConfig?
    private var bgTaskRegistered = false
    private init() {}

    /// Call once in AppDelegate.didFinishLaunching — before any JS initialize()
    public func registerForBackgroundTask() {
        guard !bgTaskRegistered else { return }
        bgTaskRegistered = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskId, using: nil) { [weak self] task in
            guard let self, let config = self.config else { task.setTaskCompleted(success: false); return }
            let t = task as! BGAppRefreshTask
            let handle = Task { await self.runCycle(config: config) }
            t.expirationHandler = { handle.cancel() }
            Task {
                await handle.value
                t.setTaskCompleted(success: true)
                self.scheduleBackgroundTask()
            }
        }
    }

    /// Called from JS via Capacitor plugin
    public func initialize(config: NetworkMetricsConfig) {
        self.config = config
        registerForBackgroundTask()
        scheduleBackgroundTask()
    }

    public func measureNow() {
        guard let config else { return }
        Task { await runCycle(config: config) }
    }

    public func getLastResult() -> String? {
        UserDefaults.standard.string(forKey: prefsKey)
    }

    public func getLastResultTimestamp() -> Int64 {
        Int64(UserDefaults.standard.double(forKey: prefsKeyAt))
    }

    private func scheduleBackgroundTask() {
        let req = BGAppRefreshTaskRequest(identifier: bgTaskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: Double((config?.intervalMinutes ?? 15) * 60))
        try? BGTaskScheduler.shared.submit(req)
    }

    // MARK: - Measurement cycle

    internal func runCycle(config: NetworkMetricsConfig) async {
        let webTargets: [WebTarget]
        if config.enableWebBrowsing {
            if let remoteUrl = config.remoteConfigUrl {
                webTargets = await RemoteConfigFetcher.fetchWebTargets(
                    url: remoteUrl, authHeader: config.authHeader, defaults: config.webTargets)
            } else {
                webTargets = config.webTargets
            }
        } else {
            webTargets = []
        }

        async let speedTask   = config.enableSpeed ? SpeedMeasurement(
            downloadDurationMs: config.speedDownloadDurationMs,
            uploadDurationMs:   config.speedUploadDurationMs,
            threadCount:        config.speedThreadCount
        ).measure() : nil
        async let socialTask  = config.enableSocialLatency ? SocialLatencyMeasurement().measure() : []
        async let streamTask  = config.enableStreaming ? StreamingMeasurement().measure() : nil
        async let dnsTask     = config.enableDns ? DnsMeasurement().measure() : nil
        async let webTask     = (config.enableWebBrowsing && !webTargets.isEmpty)
                                  ? WebBrowsingMeasurement(targets: webTargets).measure() : []

        let speed       = await speedTask
        let social      = await socialTask
        let streaming   = await streamTask
        let dns         = await dnsTask
        let webBrowsing = await webTask

        let udp: UdpResult?
        if config.enablePacketLoss && !config.udpHost.isEmpty {
            udp = await PacketLossMeasurement(host: config.udpHost,
                                              udpPort: config.udpPort,
                                              tcpPort: config.tcpPort).measure()
        } else {
            udp = nil
        }

        let network = await NetworkContextMeasurement().measure()
        let device  = DeviceMeasurement().measure()
        let geo     = await GeoMeasurement().measure()

        let loss   = udp?.lossPercent ?? 0
        let mos    = speed.map { MosCalculator.calculate(latencyMs: $0.latencyMs, jitterMs: $0.jitterMs, lossPercent: loss) }
        let scores = speed.map { QualityScoresCalculator.calculate(downloadMbps: $0.downloadMbps, latencyMs: $0.latencyMs, jitterMs: $0.jitterMs, lossPercent: loss) }

        let deviceId = await MainActor.run { UIDevice.current.identifierForVendor?.uuidString ?? "unknown" }
        let record = NetworkMetricsRecord(
            testId:        UUID().uuidString,
            deviceId:      deviceId,
            timestamp:     iso8601(),
            sdkVersion:    sdkVersion,
            speed:         speed,
            udpPacketLoss: udp,
            streaming:     streaming,
            socialLatency: social,
            dns:           dns,
            webBrowsing:   webBrowsing,
            network:       network,
            geo:           geo,
            device:        device,
            scores:        scores,
            mos:           mos
        )

        if let data = try? JSONEncoder().encode(record),
           let json = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: prefsKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970 * 1000, forKey: prefsKeyAt)
        }

        await postRecord(record: record, config: config)
    }

    private func postRecord(record: NetworkMetricsRecord, config: NetworkMetricsConfig) async {
        guard let url = URL(string: config.backendUrl),
              let body = try? JSONEncoder().encode(record) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth = config.authHeader { req.setValue(auth, forHTTPHeaderField: "Authorization") }
        _ = try? await URLSession.shared.data(for: req)
    }

    private func iso8601() -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.string(from: Date())
    }
}
