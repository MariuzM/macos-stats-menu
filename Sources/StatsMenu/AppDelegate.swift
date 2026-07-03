import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = StatsEngine(interval: 2.0)
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusItemController(engine: engine)
        engine.start()
    }
}
