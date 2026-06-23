import AppKit
@preconcurrency import ApplicationServices

// Thin Swift wrapper around the C-based Accessibility API.
extension AXUIElement {

    // MARK: - Identity

    var pid: pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(self, &p)
        return p
    }

    var title: String? { string(kAXTitleAttribute) }

    // Stable system-assigned ID for this window — does NOT change when tab title changes.
    // Used as the TilingEngine key so windows don't inherit stale snap state after
    // title changes (e.g. Chrome "New Tab" colliding with a previous window's record).
    var cgWindowID: CGWindowID? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, "AXWindowID" as CFString, &ref) == .success,
              let num = ref as? NSNumber else { return nil }
        return CGWindowID(num.uint32Value)
    }

    // MARK: - Navigation

    var focusedWindow: AXUIElement?     { element(kAXFocusedWindowAttribute) }
    var mainWindow: AXUIElement?        { element(kAXMainWindowAttribute) }
    var focusedUIElement: AXUIElement?  { element(kAXFocusedUIElementAttribute) }
    var parent: AXUIElement?            { element(kAXParentAttribute) }
    var role: String?                   { string(kAXRoleAttribute) }

    // MARK: - Geometry (AX / Quartz coordinates)

    var axPosition: CGPoint? { cgPoint(kAXPositionAttribute) }
    var axSize: CGSize?      { cgSize(kAXSizeAttribute) }

    func setPosition(_ pt: CGPoint) { setAXValue(kAXPositionAttribute, value: pt, kind: .cgPoint) }
    func setSize(_ sz: CGSize)      { setAXValue(kAXSizeAttribute,     value: sz, kind: .cgSize)  }

    // MARK: - Bool attributes

    func set(_ key: String, _ value: Bool) {
        AXUIElementSetAttributeValue(self, key as CFString, value as CFTypeRef)
    }

    // MARK: - Private

    private func string(_ key: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, key as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private func element(_ key: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, key as CFString, &ref) == .success,
              let r = ref else { return nil }
        return (r as! AXUIElement)
    }

    private func cgPoint(_ key: String) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, key as CFString, &ref) == .success,
              let r = ref else { return nil }
        var pt = CGPoint.zero
        guard AXValueGetValue(r as! AXValue, .cgPoint, &pt) else { return nil }
        return pt
    }

    private func cgSize(_ key: String) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, key as CFString, &ref) == .success,
              let r = ref else { return nil }
        var sz = CGSize.zero
        guard AXValueGetValue(r as! AXValue, .cgSize, &sz) else { return nil }
        return sz
    }

    private func setAXValue(_ key: String, value: CGPoint, kind: AXValueType) {
        var v = value
        guard let axVal = AXValueCreate(kind, &v) else { return }
        AXUIElementSetAttributeValue(self, key as CFString, axVal)
    }

    private func setAXValue(_ key: String, value: CGSize, kind: AXValueType) {
        var v = value
        guard let axVal = AXValueCreate(kind, &v) else { return }
        AXUIElementSetAttributeValue(self, key as CFString, axVal)
    }
}
