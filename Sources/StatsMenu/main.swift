import AppKit

if CommandLine.arguments.contains("--print") {
    let engine = StatsEngine()
    let netProcs = NetworkProcessMonitor()
    engine.sampleOnce()
    _ = netProcs.sample()
    Thread.sleep(forTimeInterval: 2.0)
    engine.sampleOnce()
    let procs = netProcs.sample()

    let mem = engine.memory
    let net = engine.network
    func rate(_ bps: Double) -> String {
        if bps >= 1_048_576 { return String(format: "%.1f MB/s", bps / 1_048_576) }
        if bps >= 1024 { return String(format: "%.0f KB/s", bps / 1024) }
        return String(format: "%.0f B/s", bps)
    }
    print(String(
        format: "CPU %.1f%%   MEM %.1f%% (%.2f / %.2f GB)   GPU %.1f%%",
        engine.cpu, mem.percent,
        Double(mem.usedBytes) / 1_073_741_824,
        Double(mem.totalBytes) / 1_073_741_824,
        engine.gpu
    ))
    print("NET  down \(rate(net.downBytesPerSec))   up \(rate(net.upBytesPerSec))")
    print("Top download:")
    for p in procs.sorted(by: { $0.downBytesPerSec > $1.downBytesPerSec }).prefix(5) where p.downBytesPerSec > 0 {
        print("  \(rate(p.downBytesPerSec))\t\(p.name)")
    }
    print("Top upload:")
    for p in procs.sorted(by: { $0.upBytesPerSec > $1.upBytesPerSec }).prefix(5) where p.upBytesPerSec > 0 {
        print("  \(rate(p.upBytesPerSec))\t\(p.name)")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
