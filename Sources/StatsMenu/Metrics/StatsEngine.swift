import Foundation

final class StatsEngine {
    static let historyLength = 60

    private(set) var cpu: Double = 0
    private(set) var memory: MemorySample = .zero
    private(set) var gpu: Double = 0
    private(set) var network: NetworkSample = .zero
    private(set) var disk: DiskSample = .zero

    private(set) var cpuHistory: [Double] = []
    private(set) var memHistory: [Double] = []
    private(set) var gpuHistory: [Double] = []
    private(set) var downHistory: [Double] = []
    private(set) var upHistory: [Double] = []
    private(set) var diskReadHistory: [Double] = []
    private(set) var diskWriteHistory: [Double] = []

    var onUpdate: (() -> Void)?

    private let cpuMonitor = CPUMonitor()
    private let memoryMonitor = MemoryMonitor()
    private let gpuMonitor = GPUMonitor()
    private let networkMonitor = NetworkMonitor()
    private let diskMonitor = DiskMonitor()

    private var interval: TimeInterval
    private var timer: Timer?

    init(interval: TimeInterval = 1.0) {
        self.interval = interval
    }

    func start() {
        sampleOnce()
        scheduleTimer()
    }

    func setInterval(_ value: TimeInterval) {
        guard value != interval else { return }
        interval = value
        if timer != nil {
            scheduleTimer()
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.sampleOnce()
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func sampleOnce() {
        cpu = cpuMonitor.sample()
        memory = memoryMonitor.sample()
        gpu = gpuMonitor.sample()
        network = networkMonitor.sample()
        disk = diskMonitor.sample()

        append(&cpuHistory, cpu)
        append(&memHistory, memory.percent)
        append(&gpuHistory, gpu)
        append(&downHistory, network.downBytesPerSec)
        append(&upHistory, network.upBytesPerSec)
        append(&diskReadHistory, disk.readBytesPerSec)
        append(&diskWriteHistory, disk.writeBytesPerSec)

        onUpdate?()
    }

    private func append(_ values: inout [Double], _ value: Double) {
        values.append(value)
        if values.count > Self.historyLength {
            values.removeFirst(values.count - Self.historyLength)
        }
    }
}
