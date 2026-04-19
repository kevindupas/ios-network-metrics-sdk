import Foundation
import BackgroundTasks
import UIKit
import os.log

private let prefsKey   = "nm_last_result"
private let prefsKeyAt = "nm_last_result_at"
private let bgTaskId   = "com.networkmetrics.refresh"
private let sdkVersion = "1.0.20"
private let log = OSLog(subsystem: "com.networkmetrics", category: "SDK")

public final class NetworkMetricsSdk {
    public static let shared = NetworkMetricsSdk()
    private var config: NetworkMetricsConfig?
    private var bgTaskRegistered = false
    private var progressCallback: ProgressCallback?
    private init() {}

    public func registerForBackgroundTask() {
        guard !bgTaskRegistered else { return }
        bgTaskRegistered = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskId, using: nil) { [weak self] task in
            guard let self, let config = self.config else { task.setTaskCompleted(success: false); return }
            let t = task as! BGAppRefreshTask
            let handle = Task.detached { await self.runCycle(config: config, skipSpeed: false) }
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

    public func setProgressCallback(_ cb: ProgressCallback?) {
        self.progressCallback = cb
    }

    public func measureNow(skipSpeed: Bool = false) {
        guard let config else { return }
        Task.detached { [config] in
            await self.runCycle(config: config, skipSpeed: skipSpeed)
        }
    }

    public func getLastResult() -> String? {
        UserDefaults.standard.string(forKey: prefsKey)
    }

    public func getLastResultTimestamp() -> Int64 {
        Int64(UserDefaults.standard.double(forKey: prefsKeyAt))
    }

    /// Fast synchronous-ish snapshot for launch UI. No network I/O beyond a
    /// single `NWPathMonitor` read to determine cellular vs Wi-Fi.
    public func getRadioSnapshot() async -> (radio: RadioResult, device: DeviceResult) {
        let radio  = await RadioMeasurement().measure()
        let device = await DeviceMeasurement().measure()
        return (radio, device)
    }

    private func scheduleBackgroundTask() {
        let req = BGAppRefreshTaskRequest(identifier: bgTaskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: Double((config?.intervalMinutes ?? 15) * 60))
        try? BGTaskScheduler.shared.submit(req)
    }

    private func emit(_ phase: MeasurementPhase, _ result: Any? = nil) {
        progressCallback?(MeasurementProgress(phase: phase, result: result))
    }

    internal func runCycle(config: NetworkMetricsConfig, skipSpeed: Bool) async {
        os_log("runCycle start (skipSpeed=%{public}@)", log: log, type: .debug, skipSpeed ? "true" : "false")

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

        let speed: SpeedResult? = (config.enableSpeed && !skipSpeed)
            ? await SpeedMeasurement(
                downloadDurationMs: config.speedDownloadDurationMs,
                uploadDurationMs:   config.speedUploadDurationMs,
                threadCount:        config.speedThreadCount
            ).measure()
            : nil
        emit(.speed, speed)

        let udp: UdpResult?
        if config.enablePacketLoss && !config.udpHost.isEmpty {
            udp = await PacketLossMeasurement(host: config.udpHost,
                                              udpPort: config.udpPort,
                                              tcpPort: config.tcpPort).measure()
        } else {
            udp = nil
        }
        emit(.packetLoss, udp)

        let streaming: StreamingResult? = config.enableStreaming
            ? await StreamingMeasurement(streamingUrl: config.streamingUrl).measure()
            : nil
        emit(.streaming, streaming)

        let social: [SocialLatencyResult] = config.enableSocialLatency
            ? await SocialLatencyMeasurement().measure()
            : []
        emit(.socialLatency, social)

        let dns: DnsResult? = config.enableDns
            ? await DnsMeasurement().measure()
            : nil
        emit(.dns, dns)

        let webBrowsing: [WebBrowsingResult] = (config.enableWebBrowsing && !webTargets.isEmpty)
            ? await WebBrowsingMeasurement(targets: webTargets).measure()
            : []
        emit(.webBrowsing, webBrowsing)

        let radio = await RadioMeasurement().measure()
        emit(.radio, radio)

        let network = await NetworkContextMeasurement().measure()
        emit(.network, network)

        let device = await DeviceMeasurement().measure()
        emit(.device, device)

        let geo = await GeoMeasurement().measure()
        emit(.geo, geo)

        let loss   = udp?.lossPercent ?? 0
        let mos    = speed.map { MosCalculator.calculate(latencyMs: $0.latencyMs, jitterMs: $0.jitterMs, lossPercent: loss) }
        let scores = speed.map { QualityScoresCalculator.calculate(downloadMbps: $0.downloadMbps, latencyMs: $0.latencyMs, jitterMs: $0.jitterMs, lossPercent: loss) }

        let deviceId = await MainActor.run { UIDevice.current.identifierForVendor?.uuidString ?? "unknown" }

        let record = NetworkMetricsRecord(
            testId:           UUID().uuidString,
            deviceId:         deviceId,
            timestamp:        iso8601(),
            sdkVersion:       sdkVersion,
            speed:            speed,
            udpPacketLoss:    udp,
            streaming:        streaming,
            socialLatency:    social,
            radio:            radio,
            network:          network,
            geo:              geo,
            device:           device,
            scores:           scores,
            mos:              mos,
            dns:              dns,
            webBrowsing:      webBrowsing,
            neighboringCells: []  // iOS: private API, always empty
        )

        if let data = try? JSONEncoder().encode(record),
           let json = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: prefsKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970 * 1000, forKey: prefsKeyAt)
            os_log("runCycle: saved result OK", log: log, type: .debug)
        }

        emit(.complete, record)
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
