import Foundation
import BackgroundTasks
import UIKit
import os.log

private let prefsKey   = "nm_last_result"
private let prefsKeyAt = "nm_last_result_at"
private let bgTaskId   = "com.networkmetrics.refresh"
private let sdkVersion = "1.0.12"
private let log = OSLog(subsystem: "com.networkmetrics", category: "SDK")

public final class NetworkMetricsSdk {
    public static let shared = NetworkMetricsSdk()
    private var config: NetworkMetricsConfig?
    private var bgTaskRegistered = false
    private init() {}

    public func registerForBackgroundTask() {
        guard !bgTaskRegistered else { return }
        bgTaskRegistered = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskId, using: nil) { [weak self] task in
            guard let self, let config = self.config else { task.setTaskCompleted(success: false); return }
            let t = task as! BGAppRefreshTask
            let handle = Task.detached { await self.runCycle(config: config) }
            t.expirationHandler = { handle.cancel() }
            Task.detached {
                await handle.value
                t.setTaskCompleted(success: true)
                self.scheduleBackgroundTask()
            }
        }
    }

    public func initialize(config: NetworkMetricsConfig) {
        self.config = config
        registerForBackgroundTask()
        scheduleBackgroundTask()
    }

    public func measureNow() {
        guard let config else { return }
        Task.detached { [config] in
            await self.runCycle(config: config)
        }
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

    internal func runCycle(config: NetworkMetricsConfig) async {
        os_log("runCycle start", log: log, type: .debug)

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

        os_log("runCycle: starting speed", log: log, type: .debug)
        let speed: SpeedResult? = config.enableSpeed
            ? await SpeedMeasurement(
                downloadDurationMs: config.speedDownloadDurationMs,
                uploadDurationMs:   config.speedUploadDurationMs,
                threadCount:        config.speedThreadCount
            ).measure()
            : nil
        os_log("runCycle: speed done", log: log, type: .debug)

        let social: [SocialLatencyResult] = config.enableSocialLatency
            ? await SocialLatencyMeasurement().measure()
            : []
        os_log("runCycle: social done", log: log, type: .debug)

        let streaming: StreamingResult? = config.enableStreaming
            ? await StreamingMeasurement().measure()
            : nil
        os_log("runCycle: streaming done", log: log, type: .debug)

        let dns: DnsResult? = config.enableDns
            ? await DnsMeasurement().measure()
            : nil
        os_log("runCycle: dns done", log: log, type: .debug)

        let webBrowsing: [WebBrowsingResult] = (config.enableWebBrowsing && !webTargets.isEmpty)
            ? await WebBrowsingMeasurement(targets: webTargets).measure()
            : []
        os_log("runCycle: webBrowsing done", log: log, type: .debug)

        let udp: UdpResult?
        if config.enablePacketLoss && !config.udpHost.isEmpty {
            udp = await PacketLossMeasurement(host: config.udpHost,
                                              udpPort: config.udpPort,
                                              tcpPort: config.tcpPort).measure()
        } else {
            udp = nil
        }
        os_log("runCycle: packetLoss done", log: log, type: .debug)

        let network = await NetworkContextMeasurement().measure()
        os_log("runCycle: network done", log: log, type: .debug)

        let device = await DeviceMeasurement().measure()
        os_log("runCycle: device done", log: log, type: .debug)

        let geo = await GeoMeasurement().measure()
        os_log("runCycle: geo done", log: log, type: .debug)

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
            os_log("runCycle: saved result OK", log: log, type: .debug)
        }

        await postRecord(record: record, config: config)
        os_log("runCycle: complete", log: log, type: .debug)
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
