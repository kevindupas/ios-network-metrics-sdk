import Foundation
import UIKit

internal struct DeviceMeasurement {
    func measure() -> DeviceResult {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        let batteryLevel = device.batteryLevel >= 0 ? Int(device.batteryLevel * 100) : nil
        let isCharging: Bool? = {
            switch device.batteryState {
            case .charging, .full: return true
            case .unplugged:       return false
            default:               return nil
            }
        }()

        let thermalStatus: String = {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal:  return "NONE"
            case .fair:     return "LIGHT"
            case .serious:  return "MODERATE"
            case .critical: return "SEVERE"
            @unknown default: return "UNKNOWN"
            }
        }()

        let ramUsed = ramUsedMb()
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        return DeviceResult(
            manufacturer: "Apple",
            model: modelIdentifier(),
            osVersion: osVersion,
            sdkInt: Int(ProcessInfo.processInfo.operatingSystemVersion.majorVersion),
            simOperatorName: nil,
            mcc: nil,
            mnc: nil,
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            ramUsedMb: ramUsed,
            cpuLoadPercent: nil,
            thermalStatus: thermalStatus
        )
    }

    private func ramUsedMb() -> Int? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int(info.phys_footprint / 1_048_576)
    }

    private func modelIdentifier() -> String {
        var sysInfo = utsname()
        uname(&sysInfo)
        return withUnsafePointer(to: &sysInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}
