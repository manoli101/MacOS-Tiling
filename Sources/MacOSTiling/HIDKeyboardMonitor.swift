import IOKit.hid
import Foundation

private let logPath = NSHomeDirectory() + "/tyler-hid.log"

func tylerLog(_ msg: String) {
    NSLog("%@", msg)
    let line = "\(Date()): \(msg)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logPath),
           let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: URL(fileURLWithPath: logPath))
        }
    }
}

// HID keyboard usage page (0x07) key codes
private let kHIDPageKeyboard: UInt32 = 0x07
private let kHIDUsageOptL:    UInt32 = 0xE2   // Left Option/Alt
private let kHIDUsageOptR:    UInt32 = 0xE6   // Right Option/Alt
private let kHIDUsageArrR:    UInt32 = 0x4F   // Right Arrow
private let kHIDUsageArrL:    UInt32 = 0x50   // Left Arrow
private let kHIDUsageArrD:    UInt32 = 0x51   // Down Arrow
private let kHIDUsageArrU:    UInt32 = 0x52   // Up Arrow

/// Captures keyboard events at the IOKit HID layer.
/// Works in UTM/QEMU VMs where CGEventTap and NSEvent monitors miss keyboard events
/// because virtio-input bypasses the Quartz session event stream.
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

        let result = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess {
            manager = mgr
            tylerLog("[Tyler] HID keyboard monitor started")
        } else {
            tylerLog("[Tyler] HID keyboard monitor open failed: \(result)")
        }
    }

    func stop() {
        guard let mgr = manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
    }

    fileprivate func handle(usage: UInt32, pressed: Bool) {
        switch usage {
        case kHIDUsageOptL, kHIDUsageOptR:
            optionDown = pressed
        case kHIDUsageArrR where pressed && optionDown:
            tylerLog("[Tyler] HID ⌥→")
            onArrow?(.right)
        case kHIDUsageArrL where pressed && optionDown:
            tylerLog("[Tyler] HID ⌥←")
            onArrow?(.left)
        case kHIDUsageArrU where pressed && optionDown:
            tylerLog("[Tyler] HID ⌥↑")
            onArrow?(.up)
        case kHIDUsageArrD where pressed && optionDown:
            tylerLog("[Tyler] HID ⌥↓")
            onArrow?(.down)
        default:
            break
        }
    }
}

// Scheduled on the main run loop — safe to use MainActor.assumeIsolated
private func hidValueCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard let context else { return }
    let elem  = IOHIDValueGetElement(value)
    guard IOHIDElementGetUsagePage(elem) == kHIDPageKeyboard else { return }
    let usage   = IOHIDElementGetUsage(elem)
    let pressed = IOHIDValueGetIntegerValue(value) != 0
    let monitor = Unmanaged<HIDKeyboardMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { monitor.handle(usage: usage, pressed: pressed) }
}
