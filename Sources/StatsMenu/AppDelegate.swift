import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = StatsEngine()
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusItemController(engine: engine)
        engine.start()
    }
}
