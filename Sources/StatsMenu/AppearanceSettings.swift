import Foundation

extension Notification.Name {
    static let menuBarAppearanceDidChange = Notification.Name("StatsMenu.menuBarAppearanceDidChange")
}

enum AppearanceSettings {
    private static let highContrastKey = "appearance.highContrastMenuBar"

    static var highContrastMenuBar: Bool {
        get { UserDefaults.standard.bool(forKey: highContrastKey) }
        set {
            guard newValue != highContrastMenuBar else { return }
            UserDefaults.standard.set(newValue, forKey: highContrastKey)
            NotificationCenter.default.post(name: .menuBarAppearanceDidChange, object: nil)
        }
    }
}
