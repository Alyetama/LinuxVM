import Foundation
import Virtualization

/// Allowed CPU/memory ranges, intersected with what this Mac actually has.
enum VMLimits {
    static let gb: UInt64 = 1_073_741_824

    static var minCPU: Int { VZVirtualMachineConfiguration.minimumAllowedCPUCount }
    static var maxCPU: Int {
        min(VZVirtualMachineConfiguration.maximumAllowedCPUCount, ProcessInfo.processInfo.processorCount)
    }

    static var minMemoryBytes: UInt64 { VZVirtualMachineConfiguration.minimumAllowedMemorySize }
    static var maxMemoryBytes: UInt64 {
        min(VZVirtualMachineConfiguration.maximumAllowedMemorySize, ProcessInfo.processInfo.physicalMemory)
    }

    static func clampCPU(_ value: Int) -> Int { min(max(value, minCPU), maxCPU) }
    static func clampMemoryGB(_ value: Int) -> Int {
        let bytes = UInt64(value) * gb
        let clamped = min(max(bytes, minMemoryBytes), maxMemoryBytes)
        return Int(clamped / gb)
    }

    static var maxMemoryGB: Int { Int(maxMemoryBytes / gb) }
}
