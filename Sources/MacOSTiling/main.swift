import AppKit

// Run as an accessory (menu bar only, no Dock icon)
NSApplication.shared.setActivationPolicy(.accessory)

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
