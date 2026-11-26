// SPDX-License-Identifier: GPL-3.0-or-later
import Darwin
import IOKit
import SwiftUI

/// CPU and memory load from public Mach host statistics. Sampled only while
/// the view showing it is on screen; nothing runs in the background.
enum SystemStats {
    struct CPUTicks: Equatable { var busy: UInt64; var total: UInt64 }

    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks   // user, system, idle, nice
        let user = UInt64(t.0), system = UInt64(t.1), idle = UInt64(t.2), nice = UInt64(t.3)
        return CPUTicks(busy: user + system + nice, total: user + system + idle + nice)
    }

    /// 0...1 load between two samples.
    static func cpuLoad(from a: CPUTicks, to b: CPUTicks) -> Double {
        guard b.total > a.total, b.busy >= a.busy else { return 0 }
        return min(Double(b.busy - a.busy) / Double(b.total - a.total), 1)
    }

    /// Used memory (active + wired + compressed) as 0...1 of physical RAM, like Activity Monitor's "Memory Used".
    static func memoryUsed() -> Double? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(getpagesize())
        let used = (UInt64(info.active_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)) * page
        return min(Double(used) / Double(ProcessInfo.processInfo.physicalMemory), 1)
    }
}

extension SystemStats {
    /// GPU busy 0...1 from the IOAccelerator "PerformanceStatistics" registry
    /// entry (public IOKit registry read; nil when the driver doesn't report it).
    static func gpuUtilization() -> Double? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                  let percent = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber else { continue }
            best = max(best ?? 0, min(percent.doubleValue / 100, 1))
        }
        return best
    }
}

/// Compact meters with a rolling 1-minute history.
struct SystemStatsView: View {
    @State private var cpu: [Double] = []
    @State private var memory: [Double] = []
    @State private var gpu: [Double] = []
    /// Decided once, so the GPU meter never pops in and shifts the row.
    @State private var hasGPU = SystemStats.gpuUtilization() != nil
    private static let samples = 30   // 30 × 2 s

    var body: some View {
        HStack(spacing: 6) {
            meter("CPU", cpu, .green)
            meter("Mem", memory, .cyan)
            if hasGPU { meter("GPU", gpu, .purple) }
        }
        .task {
            var last = SystemStats.cpuTicks()
            if let m = SystemStats.memoryUsed() { push(&memory, m) }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                let now = SystemStats.cpuTicks()
                if let last, let now { push(&cpu, SystemStats.cpuLoad(from: last, to: now)) }
                last = now
                if let m = SystemStats.memoryUsed() { push(&memory, m) }
                if hasGPU, let g = SystemStats.gpuUtilization() { push(&gpu, g) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// No animation: a Shape path with a changing point count can't interpolate and would flicker.
    private func push(_ list: inout [Double], _ value: Double) {
        list.append(value)
        if list.count > Self.samples { list.removeFirst(list.count - Self.samples) }
    }

    private func meter(_ title: String, _ values: [Double], _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text(title).foregroundStyle(Color.secondaryText)
                Spacer(minLength: 0)
                Text(values.last.map { "\(Int(($0 * 100).rounded()))%" } ?? "–").foregroundStyle(.white)
            }
            .font(.system(size: 9, weight: .semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            Sparkline(values: values, count: Self.samples)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .background(Sparkline(values: values, count: Self.samples, closed: true).fill(tint.opacity(0.15)))
                .frame(width: 46, height: 14)
        }
        .frame(width: 46, alignment: .leading)   // fixed slot: changing digits never move the row
        .accessibilityLabel("\(title) \(Int(((values.last ?? 0) * 100).rounded())) percent")
    }
}

/// Right-aligned history line (newest on the right).
struct Sparkline: Shape {
    var values: [Double]
    var count: Int
    var closed = false

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard values.count > 1 else { return p }
        let step = rect.width / CGFloat(max(count - 1, 1))
        let start = rect.maxX - step * CGFloat(values.count - 1)
        let points = values.enumerated().map { CGPoint(x: start + step * CGFloat($0), y: rect.maxY - rect.height * CGFloat($1)) }
        p.move(to: points[0])
        points.dropFirst().forEach { p.addLine(to: $0) }
        if closed {
            p.addLine(to: CGPoint(x: points.last!.x, y: rect.maxY))
            p.addLine(to: CGPoint(x: points[0].x, y: rect.maxY))
            p.closeSubpath()
        }
        return p
    }
}
