import Darwin
import Foundation
import os

/// `task_info(TASK_VM_INFO)` memory facts (what jetsam counts).
enum MemoryStats {
    struct Snapshot: Equatable, Sendable {
        /// `phys_footprint` bytes.
        var footprint: UInt64
        /// `ledger_phys_footprint_peak` (process lifetime peak), when the kernel reports rev3+.
        var ledgerPeak: UInt64?
        /// `os_proc_available_memory()` (bytes left before the jetsam limit); nil when 0 (simulator).
        var available: UInt64?
    }

    static func mb(_ bytes: UInt64) -> Double { Double(bytes) / 1_048_576 }

    static func snapshot() -> Snapshot? {
        var info = task_vm_info_data_t()
        let full = MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        var count = mach_msg_type_number_t(full)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: full) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let returnedBytes = Int(count) * MemoryLayout<natural_t>.size
        var ledger: UInt64?
        if let off = MemoryLayout<task_vm_info_data_t>.offset(of: \task_vm_info_data_t.ledger_phys_footprint_peak),
           returnedBytes >= off + MemoryLayout<Int64>.size, info.ledger_phys_footprint_peak > 0 {
            ledger = UInt64(info.ledger_phys_footprint_peak)
        }
        let avail = UInt64(os_proc_available_memory())
        return Snapshot(footprint: info.phys_footprint, ledgerPeak: ledger, available: avail > 0 ? avail : nil)
    }
}

/// Samples `phys_footprint` every `interval` on a private utility queue and keeps the max.
final class MemorySampler: @unchecked Sendable {
    let interval: TimeInterval
    private let queue = DispatchQueue(label: "com.ragnus.vp.memory-sampler", qos: .utility)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var peak: UInt64 = 0
    private var count = 0

    init(interval: TimeInterval = 0.1) { self.interval = interval }

    func start() {
        sample()
        let t = DispatchSource.makeTimerSource(queue: queue)
        let ms = max(1, Int(interval * 1000))
        t.schedule(deadline: .now() + .milliseconds(ms), repeating: .milliseconds(ms), leeway: .milliseconds(max(1, ms / 10)))
        t.setEventHandler { [weak self] in self?.sample() }
        lock.lock(); timer = t; lock.unlock()
        t.resume()
    }

    /// Stops sampling (takes one last sample). Returns the max footprint and the sample count.
    @discardableResult
    func stop() -> (peak: UInt64, samples: Int) {
        lock.lock(); let t = timer; timer = nil; lock.unlock()
        t?.cancel()
        sample()
        lock.lock(); defer { lock.unlock() }
        return (peak, count)
    }

    private func sample() {
        guard let s = MemoryStats.snapshot() else { return }
        lock.lock()
        peak = max(peak, s.footprint)
        count += 1
        lock.unlock()
    }
}
