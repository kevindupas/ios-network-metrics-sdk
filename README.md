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
```

### Read last result

```swift
if let json = NetworkMetricsSdk.shared.getLastResult() {
    let ts = NetworkMetricsSdk.shared.getLastResultTimestamp() // ms since epoch
    print(json)
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
| CPU load % | ❌ | ✅ |
| MCC / MNC / Operator | ❌ CTCarrier deprecated | ✅ |
| RSRP / RSRQ / Cell ID | ❌ Private API | ✅ |
| Neighbouring cells | ❌ Private API | ✅ |
| 5G NSA/SA detection | ❌ No public API | ✅ |
| VoLTE / VoNR | ❌ No public API | ✅ |
| Background scheduling guaranteed | ⚠️ BGAppRefresh best-effort | ✅ WorkManager |
| MOS G.107 | ✅ | ✅ |
| QoS scores (streaming/gaming/RTC) | ✅ | ✅ |

## Changelog

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
