import ApplicationServices
import Foundation

// No XCTest/Xcode dependency: this suite also runs with Command Line Tools.
@main
@MainActor
enum RegressionTests {
    enum Failure: Error { case assertion(String) }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure.assertion(message) }
    }

    static func rejectsInvalidValue(_ body: () throws -> Void) throws {
        do {
            try body()
            throw Failure.assertion("Expected an invalid-value error")
        } catch FocusTrackingError.invalidValue { }
    }

    static func test(_ name: String, _ body: () throws -> Void) throws {
        try body()
        print("PASS: \(name)")
    }

    static func main() throws {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let cases: [(String, CGRect, CGRect)] = [
            ("primary display", CGRect(x: 100, y: 100, width: 600, height: 400),
             CGRect(x: 100, y: 580, width: 600, height: 400)),
            ("display above primary", CGRect(x: 200, y: -800, width: 600, height: 400),
             CGRect(x: 200, y: 1480, width: 600, height: 400)),
            ("display below primary", CGRect(x: 200, y: 1500, width: 600, height: 400),
             CGRect(x: 200, y: -820, width: 600, height: 400)),
            ("display left of primary", CGRect(x: -1700, y: 300, width: 600, height: 400),
             CGRect(x: -1700, y: 380, width: 600, height: 400)),
            ("offset display right of primary", CGRect(x: 2100, y: -200, width: 600, height: 400),
             CGRect(x: 2100, y: 880, width: 600, height: 400)),
            ("partially offscreen window", CGRect(x: -20, y: -30, width: 600, height: 400),
             CGRect(x: -20, y: 710, width: 600, height: 400))
        ]
        for (name, input, expected) in cases {
            try test(name) {
                try require(WindowGeometry.cocoaRect(from: input, primaryScreen: primary) == expected,
                            "Wrong coordinate conversion for \(name)")
            }
        }
        try test("invalid geometry is rejected") {
            let invalid = [CGRect(x: 0, y: 0, width: 0, height: 100),
                           CGRect(x: 0, y: 0, width: -20, height: 100),
                           CGRect(x: 0, y: 0, width: 100, height: -20),
                           CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100),
                           CGRect(x: 0, y: CGFloat.infinity, width: 100, height: 100)]
            for frame in invalid {
                try require(WindowGeometry.cocoaRect(from: frame, primaryScreen: primary) == nil,
                            "Invalid frame accepted: \(frame)")
            }
            try require(WindowGeometry.cocoaRect(from: cases[0].1, primaryScreen: .zero) == nil,
                        "A missing display must not yield a border")
        }

        let application = AXUIElementCreateApplication(101)
        let window = AXUIElementCreateApplication(102)
        let control = AXUIElementCreateApplication(103)
        try test("focused-window attribute is authoritative") {
            let reader = AccessibilityWindow { _, attribute in
                try require(attribute == kAXFocusedWindowAttribute, "Unexpected control lookup")
                return window
            }
            let result = try reader.focusedWindow(in: application)
            try require(result.map { CFEqual($0, window) } == true, "Focused window lost")
        }
        try test("no focused window never falls back to an unrelated control") {
            let reader = AccessibilityWindow { _, attribute in
                try require(attribute == kAXFocusedWindowAttribute, "Unexpected fallback")
                return nil
            }
            let result = try reader.focusedWindow(in: application)
            try require(result == nil, "An unfocused app must have no border")
        }
        try test("unsupported focused-window attribute resolves a control's containing window") {
            let reader = AccessibilityWindow { element, attribute in
                switch attribute {
                case kAXFocusedWindowAttribute:
                    throw FocusTrackingError.accessibility("Read focus", .attributeUnsupported)
                case kAXFocusedUIElementAttribute: return control
                case kAXRoleAttribute: return kAXTextFieldRole as CFString
                case kAXWindowAttribute:
                    try require(CFEqual(element, control), "Wrong element in fallback")
                    return window
                default: throw Failure.assertion("Unexpected attribute: \(attribute)")
                }
            }
            let result = try reader.focusedWindow(in: application)
            try require(result.map { CFEqual($0, window) } == true, "Containing window lost")
        }
        try test("a focused window itself needs no containing-window attribute") {
            let reader = AccessibilityWindow { _, attribute in
                switch attribute {
                case kAXFocusedWindowAttribute:
                    throw FocusTrackingError.accessibility("Read focus", .attributeUnsupported)
                case kAXFocusedUIElementAttribute: return window
                case kAXRoleAttribute: return kAXWindowRole as CFString
                default: throw Failure.assertion("Unexpected attribute: \(attribute)")
                }
            }
            let result = try reader.focusedWindow(in: application)
            try require(result.map { CFEqual($0, window) } == true, "Window fallback failed")
        }
        try test("a control with no containing window is never highlighted") {
            let reader = AccessibilityWindow { _, attribute in
                switch attribute {
                case kAXFocusedWindowAttribute:
                    throw FocusTrackingError.accessibility("Read focus", .attributeUnsupported)
                case kAXFocusedUIElementAttribute: return control
                case kAXRoleAttribute: return kAXTextFieldRole as CFString
                case kAXWindowAttribute: return nil
                default: throw Failure.assertion("Unexpected attribute: \(attribute)")
                }
            }
            let result = try reader.focusedWindow(in: application)
            try require(result == nil, "A control was used as a window")
        }
        var position = CGPoint(x: -1700, y: 300)
        var size = CGSize(width: 600, height: 400)
        let pointValue = AXValueCreate(.cgPoint, &position)!
        let sizeValue = AXValueCreate(.cgSize, &size)!
        try test("geometry uses documented position and size attributes") {
            let reader = AccessibilityWindow { _, attribute in
                switch attribute {
                case kAXPositionAttribute: return pointValue
                case kAXSizeAttribute: return sizeValue
                default: throw Failure.assertion("Unexpected geometry attribute: \(attribute)")
                }
            }
            let frame = try reader.frame(of: window)
            try require(frame == CGRect(origin: position, size: size), "Geometry was decoded incorrectly")
        }
        try test("missing geometry yields no frame") {
            let reader = AccessibilityWindow { _, _ in nil }
            let frame = try reader.frame(of: window)
            try require(frame == nil, "Missing geometry must not create a zero frame")
        }
        try test("wrong CF types and wrong AXValue kinds fail explicitly") {
            try rejectsInvalidValue { _ = try AccessibilityWindow.point(from: "invalid" as CFString) }
            try rejectsInvalidValue { _ = try AccessibilityWindow.point(from: sizeValue) }
            try rejectsInvalidValue { _ = try AccessibilityWindow.size(from: pointValue) }
            let reader = AccessibilityWindow { _, _ in "not a window" as CFString }
            try rejectsInvalidValue { _ = try reader.focusedWindow(in: application) }
        }
        try test("permission and messaging errors propagate rather than triggering a fallback") {
            for failure in [AXError.apiDisabled, .cannotComplete] {
                let reader = AccessibilityWindow { _, _ in
                    throw FocusTrackingError.accessibility("Read focus", failure)
                }
                do {
                    _ = try reader.focusedWindow(in: application)
                    throw Failure.assertion("Accessibility failure was swallowed")
                } catch let FocusTrackingError.accessibility(_, actual) {
                    try require(actual == failure, "Wrong error propagated")
                }
            }
        }
        print("All regression tests passed.")
    }
}
