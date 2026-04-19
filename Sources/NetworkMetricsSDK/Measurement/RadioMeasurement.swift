import Foundation
import CoreTelephony
import Network

internal struct RadioMeasurement {

    func measure() async -> RadioResult {
        let tech       = await detectConnectionType()
        let networkGen = detectNetworkGeneration()
        let isRoaming  = detectRoaming()

        // iOS never exposes RSRP, RSRQ, SINR, RSSI, CQI, cell ID, PCI, TAC, LAC,
        // EARFCN, bandwidth, PSC, VoLTE/VoNR availability, or 5G NSA/SA mode to
        // third-party apps. Returned as nil / false by design.
        return RadioResult(
            rsrp: nil,
            rsrq: nil,
            sinr: nil,
            rssi: nil,
            cqi: nil,
            ci: nil,
            pci: nil,
            tac: nil,
            lac: nil,
            earfcn: nil,
            bandwidth: nil,
            psc: nil,
            isNrAvailable: networkGen == "5G",
            isVoLteAvailable: false,
            isVoNrAvailable: false,
            isRoaming: isRoaming,
            nrMode: nil,
            networkGeneration: networkGen,
            signalStrengthLevel: "UNKNOWN",
            technology: tech
        )
    }

    private func detectConnectionType() async -> String {
        await withCheckedContinuation { cont in
            let monitor = NWPathMonitor()
            var settled = false
            monitor.pathUpdateHandler = { path in
                guard !settled else { return }
                settled = true
                monitor.cancel()
                let type: String
                if path.usesInterfaceType(.wifi)         { type = "WiFi" }
                else if path.usesInterfaceType(.cellular) { type = "cellular" }
                else if path.status == .satisfied         { type = "other" }
                else                                       { type = "none" }
                cont.resume(returning: type)
            }
            monitor.start(queue: .global())
        }
    }

    private func detectNetworkGeneration() -> String {
        let info = CTTelephonyNetworkInfo()
        let rats = info.serviceCurrentRadioAccessTechnology?.values.compactMap { $0 } ?? []
        guard let rat = rats.first else { return "UNKNOWN" }
        switch rat {
        case CTRadioAccessTechnologyGPRS,
             CTRadioAccessTechnologyEdge,
             CTRadioAccessTechnologyCDMA1x:
            return "2G"
        case CTRadioAccessTechnologyWCDMA,
             CTRadioAccessTechnologyHSDPA,
             CTRadioAccessTechnologyHSUPA,
             CTRadioAccessTechnologyCDMAEVDORev0,
             CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB,
             CTRadioAccessTechnologyeHRPD:
            return "3G"
        case CTRadioAccessTechnologyLTE:
            return "4G"
        default:
            if #available(iOS 14.1, *) {
                if rat == CTRadioAccessTechnologyNRNSA || rat == CTRadioAccessTechnologyNR {
                    return "5G"
                }
            }
            return "UNKNOWN"
        }
    }

    private func detectRoaming() -> Bool {
        // CTCarrier.isoCountryCode deprecated iOS 16.4+, but still works iOS 14–16.3
        let info = CTTelephonyNetworkInfo()
        guard let carriers = info.serviceSubscriberCellularProviders else { return false }
        // Heuristic: if MCC missing or "65535" placeholder, cannot determine → false
        for carrier in carriers.values {
            guard let mcc = carrier.mobileCountryCode,
                  mcc != "65535", !mcc.isEmpty else { continue }
            // Real roaming detection requires comparing home MCC with serving MCC,
            // neither fully exposed on iOS. Return false as best-effort default.
            return false
        }
        return false
    }
}
