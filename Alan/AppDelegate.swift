//
//  AppDelegate.swift
//  Alan
//
//  Created by Tyler Hall on 11/26/25.
//

import Cocoa
import ApplicationServices

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController?

    let prefsWindowController: PrefsWindowController = {
        return PrefsWindowController(windowNibName: String(describing: PrefsWindowController.self))
    }()

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        UserDefaults.standard.register(defaults: [
            Key.enabled: true,
            Key.width: 5,
            Key.inset: 4,
            Key.hideDock: false
        ])

        if UserDefaults.standard.bool(forKey: Key.hideDock) == true {
            NSApp.setActivationPolicy(.accessory)
        }

        let controller = StatusBarController(onToggle: { enabled in
            if enabled {
                guard AXIsProcessTrusted() else {
                    throw NSError(domain: "studio.retina.Alan", code: Int(AXError.apiDisabled.rawValue), userInfo: [
                        NSLocalizedDescriptionKey: "Allow Alan in System Settings → Privacy & Security → Accessibility, then try again."
                    ])
                }
                try FocusHighlighter.shared.start()
            } else {
                FocusHighlighter.shared.stop()
            }
            UserDefaults.standard.set(enabled, forKey: Key.enabled)
        }, onOptions: { [weak self] in
            self?.showPrefs(nil)
        })
        statusBarController = controller

        // A paused app still provides its icon, Options, and Quit without asking
        // for Accessibility permission until highlighting is enabled again.
        guard UserDefaults.standard.bool(forKey: Key.enabled) else { return }
        guard requestAccessibilityPermissionIfNeeded() else { return }
        do {
            try controller.setEnabled(true)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Window Tracking Could Not Start"
            alert.informativeText = String(describing: error)
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        FocusHighlighter.shared.stop()
        statusBarController?.remove()
    }

    private func requestAccessibilityPermissionIfNeeded() -> Bool {
        let options: CFDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        let trusted = AXIsProcessTrustedWithOptions(options)

        guard trusted else {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess") {
                NSWorkspace.shared.open(url)
            }

            // Give the user a clear message and quit so they can enable it
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = """
            Alan needs Accessibility permission to highlight the focused window.

            Please open System Settings → Privacy & Security → Accessibility
            and enable “Alan”.

            Then relaunch Alan.
            """
            alert.addButton(withTitle: "Quit")
            alert.runModal()

            NSApp.terminate(nil)
            return false
        }
        return true
    }

    @IBAction func showPrefs(_ sender: AnyObject?) {
        NSApp.activate()
        prefsWindowController.showWindow(nil)
        prefsWindowController.window?.makeKeyAndOrderFront(nil)
    }
}
