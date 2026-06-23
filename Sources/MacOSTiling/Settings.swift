import Foundation

@MainActor
enum Settings {
    static var windowGap: Int {
        get { UserDefaults.standard.integer(forKey: "windowGap") }
        set { UserDefaults.standard.set(newValue, forKey: "windowGap"); notify() }
    }

    static var showStatusIndicators: Bool {
        get { UserDefaults.standard.object(forKey: "showStatusIndicators") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showStatusIndicators"); notify() }
    }

    static func reset() {
        ["windowGap", "showStatusIndicators"].forEach { UserDefaults.standard.removeObject(forKey: $0) }
        notify()
    }

    private static func notify() {
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}

extension Notification.Name {
    static let settingsChanged = Notification.Name("TylerSettingsChanged")
}
