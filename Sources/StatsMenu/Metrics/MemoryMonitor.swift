import Foundation

struct MemorySample {
    let usedBytes: UInt64
    let totalBytes: UInt64

    var percent: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100 : 0
    }

    static let zero = MemorySample(usedBytes: 0, totalBytes: 0)
}

final class MemoryMonitor {
    private let host = mach_host_self()
    private let total = ProcessInfo.processInfo.physicalMemory
    private let pageSize: UInt64 = {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return UInt64(size)
    }()

    func sample() -> MemorySample {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return MemorySample(usedBytes: 0, totalBytes: total)
        }
        let active = UInt64(stats.active_count)
        let wired = UInt64(stats.wire_count)
        let compressed = UInt64(stats.compressor_page_count)
        let used = (active + wired + compressed) * pageSize
        return MemorySample(usedBytes: used, totalBytes: total)
    }
}
