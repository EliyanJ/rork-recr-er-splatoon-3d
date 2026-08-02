import Darwin
import Foundation

/// Snapshot of the app's live resource usage, published for the in-match
/// performance overlay (Réglages → Affichage → Moniteur performances).
///
/// GPU note: iOS does not expose a per-app GPU utilization figure to apps
/// (that counter is private to Instruments/Xcode). The frame time is the
/// honest proxy shown instead — the display pipeline is GPU-bound whenever
/// frame time rises while CPU stays low.
struct PerfStats: Equatable {
    /// Rendered frames per second, averaged over the sampling window.
    let fps: Int
    /// Average time per frame in milliseconds over the window.
    let frameMs: Double
    /// Whole-process CPU usage in percent (100 = one full core; a multi-core
    /// phone can legitimately exceed 100).
    let cpuPercent: Double
    /// Physical memory footprint in MB — the figure iOS uses for jetsam.
    let memoryMB: Int
}

/// Mach-based samplers for the process's CPU and memory usage. Off the UI
/// types on purpose: these are pure syscall wrappers, safe from any thread.
nonisolated enum PerfSampler {
    /// Sum of every live thread's CPU usage, in percent of one core.
    static func cpuUsagePercent() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threads = threadList else { return 0 }
        defer {
            let size = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), size)
        }
        var total: Double = 0
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(
                MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size
            )
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            guard result == KERN_SUCCESS, info.flags & TH_FLAGS_IDLE == 0 else { continue }
            total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
        }
        return total
    }

    /// Raw hardware model identifier (e.g. "iPhone15,4") — the only reliable
    /// way to know which phone produced a report.
    static func deviceModelIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (simulateur)"
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { raw -> String in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return machine.isEmpty ? "inconnu" : machine
    }

    /// Physical footprint in MB — matches Xcode's memory gauge, unlike
    /// resident size which overcounts shared pages.
    static func memoryFootprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.phys_footprint / 1_048_576)
    }
}
