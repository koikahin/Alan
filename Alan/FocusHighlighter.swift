import AppKit
import ApplicationServices
import os

@MainActor
final class FocusHighlighter: NSObject {
    static let shared = FocusHighlighter()

    private let highlightWindow = HighlightWindow()
    private let accessibility = AccessibilityWindow()
    private let logger = Logger(subsystem: "studio.retina.Alan", category: "FocusTracking")
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var applicationPID: pid_t?
    private var observedWindow: AXUIElement?
    private var windowNotifications: [String] = []
    private var pendingRefresh: DispatchWorkItem?
    private var lastFrame: CGRect?
    private var started = false
    private var suspended = false
    private let retryDelays: [TimeInterval] = [0.05, 0.15, 0.5]

    private override init() { super.init() }

    func start() throws {
        guard !started else { return }
        // A timeout on one AX element does not apply to its children. Set the
        // process-wide timeout so an unresponsive app cannot stall all tracking.
        let error = AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
        guard error == .success else {
            throw FocusTrackingError.accessibility("Set query timeout", error)
        }
        started = true
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceCenter.addObserver(self, selector: #selector(environmentChanged), name: name, object: nil)
        }
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification] {
            workspaceCenter.addObserver(self, selector: #selector(suspendTracking), name: name, object: nil)
        }
        for name in [NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceCenter.addObserver(self, selector: #selector(resumeTracking), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        requestRefresh()
    }

    func stop() {
        started = false
        suspended = false
        pendingRefresh?.cancel()
        pendingRefresh = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        disconnectApplication()
        hideBorder()
    }

    func forceUpdate() {
        guard let lastFrame, highlightWindow.isVisible else { return }
        highlightWindow.updateFrame(to: lastFrame)
    }

    @objc private func environmentChanged() {
        // Never leave the old app's border visible during a Space/app change.
        hideBorder()
        requestRefresh()
    }

    @objc private func suspendTracking() {
        suspended = true
        pendingRefresh?.cancel()
        pendingRefresh = nil
        hideBorder()
    }

    @objc private func resumeTracking() {
        suspended = false
        disconnectApplication()
        requestRefresh()
    }

    private func requestRefresh() {
        guard started, !suspended else { return }
        pendingRefresh?.cancel()
        enqueueRefresh(attempt: 0, delay: 0)
    }

    private func enqueueRefresh(attempt: Int, delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in self?.refresh(attempt: attempt) }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func refresh(attempt: Int) {
        pendingRefresh = nil
        guard started, !suspended else { return }
        do {
            guard let frontmost = NSWorkspace.shared.frontmostApplication, !frontmost.isTerminated else {
                disconnectApplication()
                hideBorder()
                return
            }
            if frontmost.processIdentifier != applicationPID || observer == nil {
                try connectApplication(pid: frontmost.processIdentifier)
            }
            guard !frontmost.isHidden, let application else {
                hideBorder()
                return
            }
            guard let window = try accessibility.focusedWindow(in: application) else {
                unobserveWindow()
                hideBorder()
                retryIfNeeded(attempt: attempt)
                return
            }
            let windowChanged = observedWindow.map { !CFEqual($0, window) } ?? true
            if windowChanged {
                unobserveWindow()
                observedWindow = window
                do {
                    try observeWindow(window)
                } catch {
                    unobserveWindow()
                    throw error
                }
            }
            guard let axFrame = try accessibility.frame(of: window) else {
                hideBorder()
                retryIfNeeded(attempt: attempt)
                return
            }
            // NSScreen.main follows keyboard focus. The first screen is the
            // menu-bar display and is the correct coordinate-system anchor.
            guard let primaryScreen = NSScreen.screens.first,
                  let frame = WindowGeometry.cocoaRect(from: axFrame, primaryScreen: primaryScreen.frame) else {
                throw FocusTrackingError.invalidValue("window/display geometry")
            }
            if windowChanged || frame != lastFrame || !highlightWindow.isVisible {
                lastFrame = frame
                highlightWindow.updateFrame(to: frame)
            }
        } catch {
            hideBorder()
            logger.error("Focus update: \(String(describing: error), privacy: .public)")
            retryIfNeeded(attempt: attempt)
        }
    }

    private func retryIfNeeded(attempt: Int) {
        // A focus/Space transition can briefly expose no window or time out.
        // Retry only this event, with a strict bound; there is no idle poller.
        guard attempt < retryDelays.count else { return }
        enqueueRefresh(attempt: attempt + 1, delay: retryDelays[attempt])
    }

    private func connectApplication(pid: pid_t) throws {
        disconnectApplication()
        let app = AXUIElementCreateApplication(pid)
        var newObserver: AXObserver?
        let error = AXObserverCreate(pid, { observer, element, notification, context in
            FocusHighlighter.accessibilityNotification(observer: observer, element: element,
                                                       notification: notification, context: context)
        }, &newObserver)
        guard error == .success, let newObserver else {
            throw FocusTrackingError.accessibility("Create observer for \(pid)", error)
        }
        var hasFocusNotification = false
        for name in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
                     kAXFocusedUIElementChangedNotification] {
            hasFocusNotification = try subscribe(newObserver, element: app, name: name) || hasFocusNotification
        }
        guard hasFocusNotification else { throw FocusTrackingError.notificationsUnavailable(pid) }
        for name in [kAXWindowCreatedNotification, kAXApplicationHiddenNotification, kAXApplicationShownNotification] {
            _ = try subscribe(newObserver, element: app, name: name)
        }
        application = app
        applicationPID = pid
        observer = newObserver
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
    }

    private func disconnectApplication() {
        unobserveWindow()
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        application = nil
        applicationPID = nil
    }

    private func observeWindow(_ window: AXUIElement) throws {
        guard let observer else { return }
        for name in [kAXMovedNotification, kAXResizedNotification,
                     kAXWindowMovedNotification, kAXWindowResizedNotification,
                     kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
                     kAXWindowDeminiaturizedNotification] {
            if try subscribe(observer, element: window, name: name) { windowNotifications.append(name) }
        }
    }

    private func unobserveWindow() {
        if let observer, let window = observedWindow {
            for name in windowNotifications {
                let error = AXObserverRemoveNotification(observer, window, name as CFString)
                // A destroyed window can invalidate its own registrations.
                if error != .success && error != .invalidUIElement && error != .notificationNotRegistered {
                    logger.error("Remove \(name, privacy: .public): AXError \(error.rawValue)")
                }
            }
        }
        windowNotifications.removeAll()
        observedWindow = nil
    }

    private func subscribe(_ observer: AXObserver, element: AXUIElement, name: String) throws -> Bool {
        let error = AXObserverAddNotification(observer, element, name as CFString,
                                              Unmanaged.passUnretained(self).toOpaque())
        switch error {
        case .success, .notificationAlreadyRegistered: return true
        case .notificationUnsupported, .notImplemented:
            logger.notice("Application does not support \(name, privacy: .public)")
            return false
        default: throw FocusTrackingError.accessibility("Observe \(name)", error)
        }
    }

    private func hideBorder() {
        highlightWindow.orderOut(nil)
        lastFrame = nil
    }

    nonisolated private static func accessibilityNotification(
        observer: AXObserver, element: AXUIElement, notification: CFString, context: UnsafeMutableRawPointer?
    ) {
        guard let context else { return }
        let highlighter = Unmanaged<FocusHighlighter>.fromOpaque(context).takeUnretainedValue()
        // This observer's source is installed exclusively on the main run loop.
        MainActor.assumeIsolated {
            // Ignore notifications from an app we have already disconnected.
            guard let current = highlighter.observer, CFEqual(current, observer) else { return }
            highlighter.requestRefresh()
        }
    }
}
