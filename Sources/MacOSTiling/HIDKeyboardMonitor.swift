import IOKit.hid
import Foundation

// HID keyboard usage page (0x07) key codes
private let kHIDPageKeyboard: UInt32 = 0x07
private let kHIDUsageOptL:    UInt32 = 0xE2   // Left Option/Alt
private let kHIDUsageOptR:    UInt32 = 0xE6   // Right Option/Alt
private let kHIDUsageArrR:    UInt32 = 0x4F
private let kHIDUsageArrL:    UInt32 = 0x50
private let kHIDUsageArrD:    UInt32 = 0x51
private let kHIDUsageArrU:    UInt32 = 0x52

/// Captures keyboard events at the IOKit HID driver layer.
/// Fallback for environments where CGEventTap and NSEvent monitors are bypassed
/// (e.g. some VM configurations). Requires Input Monitoring permission.
@MainActor
final class HIDKeyboardMonitor {

    var onArrow: ((Direction) -> Void)?

    private var manager: IOHIDManager?
    private var optionDown = false

    func start() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        IOHIDManagerSetDeviceMatching(mgr, [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String:     kHIDUsage_GD_Keyboard
        ] as CFDictionary)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(mgr, hidValueCallback, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        guard IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            NSLog("[Tyler] HID monitor failed to open")
            return
        }
        manager = mgr
    }

    func stop() {
        guard let mgr = manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
    }

    fileprivate func handle(page: UInt32, usage: UInt32, pressed: Bool) {
        guard page == kHIDPageKeyboard else { return }
        switch usage {
        case kHIDUsageOptL, kHIDUsageOptR:
            optionDown = pressed
        case kHIDUsageArrR where pressed && optionDown:
            onArrow?(.right)
        case kHIDUsageArrL where pressed && optionDown:
            onArrow?(.left)
        case kHIDUsageArrU where pressed && optionDown:
            onArrow?(.up)
        case kHIDUsageArrD where pressed && optionDown:
            onArrow?(.down)
        default:
            break
        }
    }
}

// Scheduled on main run loop — safe to use MainActor.assumeIsolated
private func hidValueCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard let context else { return }
    let elem    = IOHIDValueGetElement(value)
    let page    = IOHIDElementGetUsagePage(elem)
    let usage   = IOHIDElementGetUsage(elem)
    let pressed = IOHIDValueGetIntegerValue(value) != 0
    let monitor = Unmanaged<HIDKeyboardMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { monitor.handle(page: page, usage: usage, pressed: pressed) }
}
