# ios-network-metrics-sdk

Native Swift SDK for comprehensive network quality measurement on iOS. Runs measurements in the foreground and schedules background refreshes via `BGAppRefreshTask`. Produces a structured JSON payload compatible with the [android-network-metrics-sdk](https://github.com/kevindupas/android-network-metrics-sdk).

## Requirements

- iOS 14+
- Swift 5.7+
- Xcode 14+

## Installation

### Swift Package Manager

In Xcode → File → Add Package Dependencies:

```
https://github.com/kevindupas/ios-network-metrics-sdk
```

Or in `Package.swift`:

```swift
.package(url: "https://github.com/kevindupas/ios-network-metrics-sdk.git", from: "1.0.0")
```

## Setup

### 1. Info.plist — Required permissions

```xml
<!-- Location -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>Used to tag network measurements with GPS coordinates.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Used to tag background network measurements with GPS coordinates.</string>

<!-- Background refresh -->
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.networkmetrics.refresh</string>
</array>
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
</array>
```

### 2. AppDelegate / App entry point

```swift
import NetworkMetricsSDK

@main
struct MyApp: App {
    init() {
        NetworkMetricsSdk.shared.initialize(config: NetworkMetricsConfig(
            backendUrl:          "https://your-backend.com/api/measurements",
            authHeader:          "Bearer YOUR_TOKEN",
            intervalMinutes:     15,
            enableSpeed:         true,
            enablePacketLoss:    true,
            enableStreaming:     true,
            enableSocialLatency: true,
            enableDns:           true,
            enableWebBrowsing:   true,
            udpHost:             "your-udp-server.com",
            udpPort:             5005,
            tcpPort:             5006
        ))
    }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

## Usage

### Trigger a measurement manually

```swift
NetworkMetricsSdk.shared.measureNow()

// skip speed test (fast cycle — useful for background refresh)
NetworkMetricsSdk.shared.measureNow(skipSpeed: true)
```

### Read last result

```swift
if let json = NetworkMetricsSdk.shared.getLastResult() {
    let ts = NetworkMetricsSdk.shared.getLastResultTimestamp() // ms since epoch
    print(json)
}
```

### Radio snapshot (fast, no network I/O)

```swift
Task {
    let snap = await NetworkMetricsSdk.shared.getRadioSnapshot()
    print(snap.radio.networkGeneration) // "4G" / "5G" / ...
    print(snap.radio.technology)        // "WiFi" / "cellular"
    print(snap.device.simOperatorName)  // Operator name (iOS 14-16.3 only)
}
```

### Per-phase progress events

```swift
NetworkMetricsSdk.shared.setProgressCallback { progress in
    switch progress.phase {
    case .speedDownloadProgress:
        if let mbps = progress.result as? Double { print("DL \(mbps) Mbps") }
    case .speed:
        if let s = progress.result as? SpeedResult { print("Speed done: \(s.downloadMbps)") }
    case .complete:
        print("Cycle complete")
    default:
        break
    }
}
```

## Configuration

| Parameter | Type | Default | Description |
|---|---|---|---|
| `backendUrl` | `String` | required | POST endpoint for measurements |
| `authHeader` | `String?` | `nil` | `Authorization` header value |
| `intervalMinutes` | `Int` | `15` | Background refresh interval (best-effort) |
| `enableSpeed` | `Bool` | `true` | Download/upload speed test via Cloudflare |
| `enablePacketLoss` | `Bool` | `true` | UDP packet loss (TCP fallback) |
| `enableStreaming` | `Bool` | `true` | HLS segment download simulation |
| `enableSocialLatency` | `Bool` | `true` | TTFB to WhatsApp/YouTube/Facebook/etc |
| `enableDns` | `Bool` | `true` | DNS resolution timing |
| `enableWebBrowsing` | `Bool` | `true` | Per-phase web timing (DNS+TCP+TLS+TTFB) |
| `udpHost` | `String` | `""` | UDP echo server host |
| `udpPort` | `Int` | `5005` | UDP port |
| `tcpPort` | `Int` | `5006` | TCP fallback port |
| `webTargets` | `[WebTarget]` | 5 defaults | Sites to probe for web browsing |
| `remoteConfigUrl` | `String?` | `nil` | URL returning `{"targets":[...]}` (1h cache) |
| `speedDownloadDurationMs` | `Int` | `10000` | Download test window |
| `speedUploadDurationMs` | `Int` | `8000` | Upload test window |
| `speedThreadCount` | `Int` | `3` | Parallel TCP streams for speed test |
| `streamingUrl` | `String?` | `nil` | HLS master playlist URL (falls back to a default test stream) |

## Payload

Same structure as android-network-metrics-sdk. Key fields:

```json
{
  "testId": "uuid",
  "deviceId": "IDFV-uuid",
  "timestamp": "2026-04-19T10:00:00Z",
  "sdkVersion": "1.0.0",
  "speed": { "downloadMbps": 12.4, "uploadMbps": 5.1, "latencyMs": 28, "jitterMs": 3.2 },
  "udpPacketLoss": { "sent": 100, "received": 97, "lossPercent": 3.0, "method": "UDP" },
  "streaming": { "startTimeMs": 1713520800000, "rebufferCount": 0, "avgBitrateKbps": 1240 },
  "socialLatency": [{ "service": "WhatsApp", "ttfbMs": 120, "reachable": true }],
  "dns": { "resolveMs": 34, "host": "www.google.com", "resolvedIps": ["142.250.74.36"], "success": true },
  "webBrowsing": [{ "name": "Google", "url": "https://www.google.com", "dnsMs": 12, "tcpMs": 28, "tlsMs": 45, "ttfbMs": 80, "totalMs": 95, "httpStatus": 200, "success": true }],
  "network": { "connectionType": "WiFi", "ip": "1.2.3.4", "asn": "AS12345", "isp": "Safaricom", "cfColo": "NBO", "isLocallyServed": true, "ipVersion": "IPv4" },
  "geo": { "lat": -1.286, "lon": 36.817, "accuracy": 10.0 },
  "device": { "manufacturer": "Apple", "model": "iPhone16,2", "osVersion": "18.0", "batteryLevel": 82, "thermalStatus": "NONE" },
  "scores": { "streaming": { "score": 4, "label": "Good" }, "gaming": { "score": 3, "label": "Average" }, "rtc": { "score": 4, "label": "Good" } },
  "mos": 4.2
}
```

## iOS vs Android feature parity

| Feature | iOS | Android |
|---|:---:|:---:|
| Speed DL/UL/Latency/Jitter | ✅ | ✅ |
| Packet loss UDP/TCP | ✅ | ✅ |
| HLS streaming simulation | ✅ FG / ⚠️ BG | ✅ |
| Social latency TTFB | ✅ | ✅ |
| DNS resolution timing | ✅ | ✅ |
| Web browsing phase timing | ✅ | ✅ |
| GPS location | ✅ | ✅ |
| ISP / ASN / CF PoP | ✅ | ✅ |
| IP version detection | ✅ | ✅ |
| Device model / OS / battery | ✅ | ✅ |
| RAM usage | ✅ | ✅ |
| Thermal state | ✅ | ✅ |
| CPU load % | ❌ Sandboxed (no `host_processor_info`) | ✅ |
| Network generation (2G/3G/4G/5G) | ✅ via CTTelephonyNetworkInfo | ✅ |
| MCC / MNC / Operator | ⚠️ iOS 14–16.3 only (placeholder `"--"` / `65535` on 16.4+) | ✅ |
| RSRP / RSRQ / SINR / RSSI / CQI | ❌ Private API | ✅ |
| Cell ID / PCI / TAC / EARFCN | ❌ Private API | ✅ |
| Neighbouring cells | ❌ Private API | ✅ |
| 5G NSA/SA detection | ❌ No public API | ✅ |
| VoLTE / VoNR availability | ❌ No public API | ✅ |
| Progress callbacks (per-phase) | ✅ `setProgressCallback` | ✅ |
| Background scheduling guaranteed | ⚠️ `BGAppRefreshTask` best-effort | ✅ WorkManager |
| MOS G.107 | ✅ | ✅ |
| QoS scores (streaming/gaming/RTC) | ✅ | ✅ |

## Changelog

### v1.0.20 — Android parity pass
- Feat: `RadioMeasurement` via `CTTelephonyNetworkInfo.serviceCurrentRadioAccessTechnology` — reports `networkGeneration` (2G/3G/4G/5G) + `technology` (WiFi/cellular). Signal fields (RSRP/RSRQ/SINR/RSSI/CQI/CI/PCI/TAC/EARFCN) remain `nil` — not exposed by public iOS APIs.
- Feat: `NetworkMetricsRecord` now carries `radio` + `neighboringCells` (always empty on iOS).
- Feat: `MeasurementProgress` enum + `setProgressCallback(_:)` — emits per-phase events during `runCycle` (speed, packetLoss, streaming, socialLatency, dns, webBrowsing, radio, network, device, geo, complete). Matches Android `MeasurementCallback`.
- Feat: `measureNow(skipSpeed:)` — allows fast cycles (skip the ~18s speed test) for background refresh budgets.
- Feat: `getRadioSnapshot()` async — fast launch-UI snapshot (radio + device), no network I/O beyond a single `NWPathMonitor` read.
- Feat: `streamingUrl` config option — override default HLS test stream.
- Algorithm alignment with Android:
  - Speed latency: 2 warmup + 12 measured HEAD probes, **stddev** jitter (not mean-absolute-deviation)
  - PacketLoss: 30 packets @ 50ms interval, 5s timeout, UDP pre-flight probe, `method` lowercase
  - Streaming: 20s budget, lowest-BANDWIDTH variant selection via regex, rebuffer on >500ms segment gap
  - SocialLatency: reachable on any 100–599 HTTP status
  - WebBrowsing: phase-only timings via `URLSessionTaskTransactionMetrics` (dns/tcp/tls/ttfb)
  - NetworkContext: ipapi.co → ipwho.is fallback chain for ASN/ISP/city, `cfServerCity` from Cloudflare locations list

### v1.0.19
- Fix: filter CTCarrier placeholder `"--"` (iOS 16+ returns `"--"` for operator name instead of nil)

### v1.0.18
- Feat: MCC/MNC/operator via CTCarrier — works on iOS 14–16.3 (common in Africa), returns nil on iOS 16.4+ where Apple returns placeholder "65535"
- Feat: loaded latency — concurrent HEAD probes during download window, measures RTT under load
- Fix: CPU load % marked as unavailable (iOS sandbox blocks `host_processor_info`)

### v1.0.17
- Fix: download speed — parallel `Task.detached` loops each downloading 10 MB chunks via `URLSession.data(from:)` until deadline. No delegate, no race condition, simple byte counting.

### v1.0.16
- Fix: download speed — switch to `URLSessionDataDelegate.didReceive(data:)` for in-memory chunk accumulation. `URLSessionDownloadTask` writes to disk first (delayed flush = 0 bytes at deadline). `dataTask` delivers chunks directly to memory, deadline timer cancels sessions and reports accumulated bytes.

### v1.0.15
- Fix: download speed — use `URLSessionDownloadTask` + `didWriteData` delegate (counts bytes written to disk per chunk, no byte-by-byte loop overhead). Multiple parallel tasks via delegate pattern.

### v1.0.14
- Fix: download speed measurement — replace `bytes(from:)` byte-by-byte iteration (too slow, loop overhead kills throughput) with `URLSessionDataDelegate` chunk-based counting

### v1.0.13
- Fix: bump minimum iOS target to 15.0 — `URLSession.bytes(from:)` requires iOS 15+

### v1.0.12
- Fix: `SpeedMeasurement.measureDownload()` — use `URLSession.bytes(from:)` streaming to measure bytes during the window instead of waiting for full 100MB download to complete

### v1.0.11
- Fix: `SpeedMeasurement.measureDownload()` — concurrent threads via `Task.detached` + `DispatchQueue` serialization

### v1.0.10
- Fix: remove all remaining `withTaskGroup` inside measurements (SocialLatency, Speed, WebBrowsing) — same Swift runtime heap corruption bug (swift#75501)
- Debug: add `os_log` at each step of `runCycle` to identify exact crash location

### v1.0.9
- Fix: `GeoMeasurement` — `CLLocationManager` must run on main thread; force via `DispatchQueue.main.async`. Guard double-resume with `settled` flag.
- Fix: `NetworkContextMeasurement` — `DispatchSemaphore.wait()` inside Swift concurrency blocks the cooperative thread pool → replaced with async `withCheckedContinuation`.

### v1.0.8
- Fix: **root cause of `freed pointer` crash** — known Swift runtime bug (swift#75501): `async let` task group cleanup causes heap corruption. Replaced all `async let` with sequential `await`. Also replaced `Task {}` with `Task.detached` in `measureNow()` to avoid inheriting main-actor context from Capacitor call site.

### v1.0.7
- Fix: **root cause of SIGABRT** — `DispatchQueue.main.sync` from main thread (Capacitor calls on main thread) causes deadlock → heap corruption. Replaced with `MainActor.run` (async, safe from any thread). `DeviceMeasurement.measure()` is now `async`.

### v1.0.6
- CI: fix release workflow — use swift build (macOS host) to validate; iOS platform not available on macos-15 runner without extra download

### v1.0.5
- CI: fix release workflow — use xcodebuild build (swift build --triple fails on CI runner)

### v1.0.4
- CI: fix release workflow (use xcodebuild build instead of xcframework)

### v1.0.3
- Fix: SIGABRT crash in `runCycle` — `UIDevice.current.identifierForVendor` called from async context, moved to `MainActor.run`

### v1.0.2
- Fix: SIGABRT crash on `measureNow()` — `UIDevice.current` battery access must be on main thread, wrapped in `DispatchQueue.main.sync`

### v1.0.1
- Fix: `BGTaskScheduler` double registration crash — add `registerForBackgroundTask()` separate from `initialize()`
- `AppDelegate` must call `NetworkMetricsSdk.shared.registerForBackgroundTask()` in `didFinishLaunching`
- `initialize()` is idempotent — safe to call from JS multiple times

### v1.0.0
- Initial release
- Speed, DNS, WebBrowsing, Social latency, Streaming, Packet loss
- Device context, GPS, Network context (Cloudflare)
- BGAppRefreshTask background scheduling
- `measureNow()` + `getLastResult()` API
- JSON payload compatible with android-network-metrics-sdk
