import AppKit

final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let engine: StatsEngine
    private var popover: NSPopover?
    private var popoverVC: PopoverViewController?
    private var outsideClickMonitor: Any?
    private var lastSignature: String = ""

    init(engine: StatsEngine) {
        self.engine = engine
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover)
        }

        engine.onUpdate = { [weak self] in self?.refresh() }
        refresh()
    }

    private func refresh() {
        let signature = StatusBarRenderer.signature(for: engine)
        if signature != lastSignature {
            lastSignature = signature
            statusItem.button?.image = StatusBarRenderer.image(for: engine)
        }
        if popover?.isShown == true {
            popoverVC?.refresh()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }

        let vc = PopoverViewController(engine: engine)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = vc
        popoverVC = vc
        self.popover = popover

        vc.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover?.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        popover?.contentViewController = nil
        popover = nil
        popoverVC = nil
        AppInfo.clearCache()
        malloc_zone_pressure_relief(nil, 0)
    }
}
