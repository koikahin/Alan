import ApplicationServices
import Foundation

enum FocusTrackingError: Error, CustomStringConvertible {
    case accessibility(String, AXError)
    case invalidValue(String)
    case notificationsUnavailable(pid_t)

    var description: String {
        switch self {
        case let .accessibility(operation, error):
            return "\(operation) failed (AXError \(error.rawValue))"
        case let .invalidValue(attribute):
            return "Invalid value for \(attribute)"
        case let .notificationsUnavailable(pid):
            return "Application \(pid) does not support focus notifications"
        }
    }
}

struct AccessibilityWindow {
    typealias ReadAttribute = (AXUIElement, String) throws -> CFTypeRef?
    private let readAttribute: ReadAttribute

    init(readAttribute: @escaping ReadAttribute = AccessibilityWindow.copyAttribute) {
        self.readAttribute = readAttribute
    }

    func focusedWindow(in application: AXUIElement) throws -> AXUIElement? {
        do {
            return try element(readAttribute(application, kAXFocusedWindowAttribute),
                               attribute: kAXFocusedWindowAttribute)
        } catch FocusTrackingError.accessibility(_, .attributeUnsupported) {
            // Some apps expose a focused control but not AXFocusedWindow.
            // Resolve its containing window; never draw around the control itself.
            guard let focused = try element(readAttribute(application, kAXFocusedUIElementAttribute),
                                            attribute: kAXFocusedUIElementAttribute) else { return nil }
            let role = try readAttribute(focused, kAXRoleAttribute) as? String
            if role == kAXWindowRole || role == kAXSheetRole { return focused }
            return try element(readAttribute(focused, kAXWindowAttribute), attribute: kAXWindowAttribute)
        }
    }

    func frame(of window: AXUIElement) throws -> CGRect? {
        guard let position = try readAttribute(window, kAXPositionAttribute),
              let size = try readAttribute(window, kAXSizeAttribute) else { return nil }
        return CGRect(origin: try Self.point(from: position), size: try Self.size(from: size))
    }

    static func point(from value: CFTypeRef) throws -> CGPoint {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            throw FocusTrackingError.invalidValue(kAXPositionAttribute)
        }
        let axValue = value as! AXValue // Type ID was checked above.
        var point = CGPoint.zero
        guard AXValueGetType(axValue) == .cgPoint, AXValueGetValue(axValue, .cgPoint, &point) else {
            throw FocusTrackingError.invalidValue(kAXPositionAttribute)
        }
        return point
    }

    static func size(from value: CFTypeRef) throws -> CGSize {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            throw FocusTrackingError.invalidValue(kAXSizeAttribute)
        }
        let axValue = value as! AXValue // Type ID was checked above.
        var size = CGSize.zero
        guard AXValueGetType(axValue) == .cgSize, AXValueGetValue(axValue, .cgSize, &size) else {
            throw FocusTrackingError.invalidValue(kAXSizeAttribute)
        }
        return size
    }

    private func element(_ value: CFTypeRef?, attribute: String) throws -> AXUIElement? {
        guard let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw FocusTrackingError.invalidValue(attribute)
        }
        return (value as! AXUIElement)
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) throws -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        switch error {
        case .success: return value
        case .noValue: return nil // An app without a focused window is normal.
        default: throw FocusTrackingError.accessibility("Read \(attribute)", error)
        }
    }
}
