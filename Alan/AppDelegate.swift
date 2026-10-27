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

    let prefsWindowController: PrefsWindowController = {
        return PrefsWindowController(windowNibName: String(describing: PrefsWindowController.self))
    }()

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        UserDefaults.standard.register(defaults: [
            Key.width: 5,
            Key.inset: 4,
            Key.hideDock: false
        ])

        if UserDefaults.standard.bool(forKey: Key.hideDock) == true {
            NSApp.setActivationPolicy(.accessory)
        }

        guard requestAccessibilityPermissionIfNeeded() else { return }
        do {
            try FocusHighlighter.shared.start()
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
        prefsWindowController.showWindow(nil)
        prefsWindowController.window?.makeKeyAndOrderFront(nil)
    }
}
