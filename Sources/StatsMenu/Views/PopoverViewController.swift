import AppKit

private enum MetricKind {
    case cpu, memory, network
}

private struct DetailItem {
    let icon: NSImage
    let name: String
    let value: String
}

final class PopoverViewController: NSViewController {
    private let engine: StatsEngine
    private let rowCount = 5
    private let networkProcesses = NetworkProcessMonitor()

    private let cpuRow = MetricRow(title: "CPU", color: .systemBlue)
    private let memRow = MetricRow(title: "Memory", color: .systemGreen)
    private let gpuRow = MetricRow(title: "GPU", color: .systemPurple)
    private let networkRow = NetworkRow()

    private var latestProcesses: [ProcessSample] = []
    private var latestNet: [NetworkProcessSample] = []

    private var activeKind: MetricKind?
    private weak var anchorView: NSView?
    private var closeWorkItem: DispatchWorkItem?

    init(engine: StatsEngine) {
        self.engine = engine
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        FlyoutController.shared.hide()
    }

    override func loadView() {
        let title = NSTextField(labelWithString: "Stats")
        title.font = .boldSystemFont(ofSize: 13)

        let settings = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")!,
                                target: self, action: #selector(openSettings))
        settings.isBordered = false
        settings.bezelStyle = .regularSquare

        let quit = NSButton(image: NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")!,
                            target: self, action: #selector(quit))
        quit.isBordered = false
        quit.bezelStyle = .regularSquare

        let header = NSStackView(views: [title, NSView(), settings, quit])
        header.orientation = .horizontal
        header.spacing = 8

        cpuRow.onHover = { [weak self] entered in self?.handleHover(.cpu, anchor: self?.cpuRow, entered: entered) }
        memRow.onHover = { [weak self] entered in self?.handleHover(.memory, anchor: self?.memRow, entered: entered) }
        networkRow.onHover = { [weak self] entered in self?.handleHover(.network, anchor: self?.networkRow, entered: entered) }

        let stack = NSStackView(views: [header, cpuRow, memRow, gpuRow, networkRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            container.widthAnchor.constraint(equalToConstant: 260),
        ])
        view = container
    }

    func refresh() {
        cpuRow.update(value: "\(Int(engine.cpu.rounded()))%", subtitle: nil, history: engine.cpuHistory)
        memRow.update(value: "\(Int(engine.memory.percent.rounded()))%",
                      subtitle: "\(formatGB(engine.memory.usedBytes)) of \(formatGB(engine.memory.totalBytes))",
                      history: engine.memHistory)
        gpuRow.update(value: "\(Int(engine.gpu.rounded()))%", subtitle: nil, history: engine.gpuHistory)
        networkRow.update(down: rate(engine.network.downBytesPerSec),
                          up: rate(engine.network.upBytesPerSec),
                          downHistory: engine.downHistory, upHistory: engine.upHistory)

        if let kind = activeKind {
            sample(for: kind)
            FlyoutController.shared.updateContent(sections: detailSections(for: kind))
        }
    }

    private func handleHover(_ kind: MetricKind, anchor: NSView?, entered: Bool) {
        guard let anchor else { return }
        if entered {
            closeWorkItem?.cancel()
            activeKind = kind
            anchorView = anchor
            sample(for: kind)
            presentDetail()
        } else {
            scheduleClose()
        }
    }

    private func scheduleClose() {
        closeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.activeKind = nil
            FlyoutController.shared.hide()
        }
        closeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func presentDetail() {
        guard let kind = activeKind, let anchor = anchorView else { return }
        FlyoutController.shared.show(sections: detailSections(for: kind), relativeTo: anchor)
    }

    private func sample(for kind: MetricKind) {
        switch kind {
        case .cpu, .memory: latestProcesses = ProcessMonitor.sample()
        case .network: latestNet = networkProcesses.sample()
        }
    }

    private func detailSections(for kind: MetricKind) -> [(String, [DetailItem])] {
        switch kind {
        case .cpu:
            let items = latestProcesses.sorted { $0.cpu > $1.cpu }.prefix(rowCount)
                .map { item(pid: $0.pid, name: $0.name, value: String(format: "%.1f%%", $0.cpu)) }
            return [("Top CPU", items)]
        case .memory:
            let items = latestProcesses.sorted { $0.memBytes > $1.memBytes }.prefix(rowCount)
                .map { item(pid: $0.pid, name: $0.name, value: formatMB($0.memBytes)) }
            return [("Top Memory", items)]
        case .network:
            let down = latestNet.filter { $0.downBytesPerSec > 0 }
                .sorted { $0.downBytesPerSec > $1.downBytesPerSec }.prefix(rowCount)
                .map { item(pid: $0.pid, name: $0.name, value: rate($0.downBytesPerSec)) }
            let up = latestNet.filter { $0.upBytesPerSec > 0 }
                .sorted { $0.upBytesPerSec > $1.upBytesPerSec }.prefix(rowCount)
                .map { item(pid: $0.pid, name: $0.name, value: rate($0.upBytesPerSec)) }
            return [("Top Download", down), ("Top Upload", up)]
        }
    }

    private func item(pid: Int, name: String, value: String) -> DetailItem {
        let info = AppInfo.lookup(pid: pid)
        return DetailItem(icon: info.icon, name: info.name ?? name, value: value)
    }

    @objc private func openSettings() {
        FlyoutController.shared.hide()
        activeKind = nil
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func formatGB(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    private func formatMB(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }

    private func rate(_ bps: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = bps
        var unit = 0
        while value >= 1000 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        let number = (unit == 0 || value >= 100)
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(number) \(units[unit])"
    }
}

private final class FlyoutController {
    static let shared = FlyoutController()

    private let detailVC = DetailListViewController(rowCount: 5)
    private let panel: NSPanel

    private init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 120),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.contentViewController = detailVC
    }

    func show(sections: [(String, [DetailItem])], relativeTo view: NSView) {
        detailVC.update(sections: sections)
        guard let window = view.window else { return }

        let size = detailVC.view.fittingSize
        panel.setContentSize(size)

        let rectInWindow = view.convert(view.bounds, to: nil)
        let screenRect = window.convertToScreen(rectInWindow)
        let gap: CGFloat = 8
        let origin = NSPoint(x: screenRect.minX - size.width - gap,
                             y: screenRect.maxY - size.height)
        panel.setFrameOrigin(origin)

        if !panel.isVisible {
            panel.orderFront(nil)
        }
    }

    func updateContent(sections: [(String, [DetailItem])]) {
        guard panel.isVisible else { return }
        detailVC.update(sections: sections)
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private final class DetailListViewController: NSViewController {
    private final class Group {
        let header = NSTextField(labelWithString: "")
        let rows: [ProcessRow]
        init(rowCount: Int) {
            rows = (0..<rowCount).map { _ in ProcessRow(width: 256) }
            header.font = .systemFont(ofSize: 10, weight: .semibold)
            header.textColor = .secondaryLabelColor
        }
    }

    private let emptyLabel = NSTextField(labelWithString: "Gathering…")
    private let groups: [Group]
    private var stack: NSStackView!

    init(rowCount: Int) {
        groups = [Group(rowCount: rowCount), Group(rowCount: rowCount)]
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        emptyLabel.font = .systemFont(ofSize: 11)
        emptyLabel.textColor = .tertiaryLabelColor

        var views: [NSView] = [emptyLabel]
        for group in groups {
            views.append(group.header)
            views += group.rows as [NSView]
        }

        stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        for group in groups.dropFirst() {
            stack.setCustomSpacing(12, after: previousView(before: group.header, in: views))
        }
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSVisualEffectView()
        container.material = .menu
        container.state = .active
        container.blendingMode = .behindWindow
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            container.widthAnchor.constraint(equalToConstant: 280),
        ])
        view = container
    }

    private func previousView(before target: NSView, in views: [NSView]) -> NSView {
        guard let idx = views.firstIndex(where: { $0 === target }), idx > 0 else { return target }
        return views[idx - 1]
    }

    func update(sections: [(String, [DetailItem])]) {
        let total = sections.reduce(0) { $0 + $1.1.count }
        emptyLabel.isHidden = total > 0

        for (i, group) in groups.enumerated() {
            if i < sections.count {
                let (title, items) = sections[i]
                group.header.stringValue = title.uppercased()
                group.header.isHidden = false
                for (j, row) in group.rows.enumerated() {
                    if j < items.count {
                        row.update(item: items[j])
                        row.isHidden = false
                    } else {
                        row.isHidden = true
                    }
                }
            } else {
                group.header.isHidden = true
                group.rows.forEach { $0.isHidden = true }
            }
        }
    }
}

class HoverStackView: NSStackView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

private final class MetricRow: HoverStackView {
    private let valueLabel = NSTextField(labelWithString: "0%")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let graph = MetricGraphView()

    init(title: String, color: NSColor) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 3

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        valueLabel.textColor = color

        let head = NSStackView(views: [titleLabel, NSView(), valueLabel])
        head.orientation = .horizontal
        head.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = .secondaryLabelColor

        graph.color = color
        graph.translatesAutoresizingMaskIntoConstraints = false

        addArrangedSubview(head)
        addArrangedSubview(subtitleLabel)
        addArrangedSubview(graph)

        NSLayoutConstraint.activate([
            head.widthAnchor.constraint(equalToConstant: 232),
            graph.widthAnchor.constraint(equalToConstant: 232),
            graph.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(value: String, subtitle: String?, history: [Double]) {
        valueLabel.stringValue = value
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.isHidden = subtitle == nil
        graph.history = history
    }
}

private final class NetworkRow: HoverStackView {
    private let downLabel = NSTextField(labelWithString: "↓ 0 B/s")
    private let upLabel = NSTextField(labelWithString: "↑ 0 B/s")
    private let graph = NetworkGraphView()

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 3

        let titleLabel = NSTextField(labelWithString: "Network")
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        downLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        downLabel.textColor = .systemTeal
        upLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        upLabel.textColor = .systemOrange

        let head = NSStackView(views: [titleLabel, NSView(), downLabel, upLabel])
        head.orientation = .horizontal
        head.spacing = 8
        head.translatesAutoresizingMaskIntoConstraints = false

        graph.translatesAutoresizingMaskIntoConstraints = false

        addArrangedSubview(head)
        addArrangedSubview(graph)

        NSLayoutConstraint.activate([
            head.widthAnchor.constraint(equalToConstant: 232),
            graph.widthAnchor.constraint(equalToConstant: 232),
            graph.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(down: String, up: String, downHistory: [Double], upHistory: [Double]) {
        downLabel.stringValue = "↓ \(down)"
        upLabel.stringValue = "↑ \(up)"
        graph.down = downHistory
        graph.up = upHistory
    }
}

private final class ProcessRow: NSStackView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")

    init(width: CGFloat) {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        distribution = .fill
        spacing = 6

        iconView.imageScaling = .scaleProportionallyDown
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.cell?.usesSingleLineMode = true
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addArrangedSubview(iconView)
        addArrangedSubview(nameLabel)
        addArrangedSubview(valueLabel)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: 18),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(item: DetailItem) {
        iconView.image = item.icon
        nameLabel.stringValue = item.name
        valueLabel.stringValue = item.value
    }
}
