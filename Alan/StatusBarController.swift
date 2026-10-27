import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let onToggle: (Bool) throws -> Void
    private let onOptions: () -> Void
    private(set) var isEnabled = false

    init(onToggle: @escaping (Bool) throws -> Void, onOptions: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onOptions = onOptions
        super.init()

        guard let button = statusItem.button,
              let image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Alan") else {
            preconditionFailure("Could not create Alan's menu bar icon")
        }
        image.isTemplate = true
        button.image = image
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityHelp("Click to toggle window highlighting. Right-click for Options and Quit.")

        menu.delegate = self
        menu.autoenablesItems = false
        let options = NSMenuItem(title: "Options…", action: #selector(showOptions), keyEquivalent: ",")
        options.target = self
        menu.addItem(options)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Alan", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        updateAppearance()
    }

    func setEnabled(_ enabled: Bool) throws {
        guard enabled != isEnabled else { return }
        // Update the icon only after the tracker successfully changes state.
        try onToggle(enabled)
        isEnabled = enabled
        updateAppearance()
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func clicked() {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            // Temporarily attach the menu so ordinary left clicks remain toggles.
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            return
        }
        do {
            try setEnabled(!isEnabled)
        } catch {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Could Not Turn Alan On"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    private func updateAppearance() {
        guard let button = statusItem.button else {
            preconditionFailure("Alan's menu bar button disappeared")
        }
        // This dims the icon without disabling its actions or its context menu.
        button.appearsDisabled = !isEnabled
        let state = isEnabled ? "On" : "Off"
        let action = isEnabled ? "turn off" : "turn on"
        button.toolTip = "Alan — \(state). Click to \(action); right-click for Options and Quit."
        button.setAccessibilityLabel("Alan, \(state)")
    }

    @objc private func showOptions() {
        onOptions()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
