import AppKit
import SwiftUI

class StatusBarController {
    private var statusItem: NSStatusItem
    private let menu = NSMenu()
    private var settingsWindow: NSWindow?
    
    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Marsin Dictation")
        }
        
        setupMenu()
        
        // Listen for recording state changes to update the icon
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(recordStateChanged(_:)),
            name: NSNotification.Name("RecordStateChanged"),
            object: nil
        )
    }
    
    private func setupMenu() {
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit Marsin Dictation", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func recordStateChanged(_ notification: Notification) {
        let isRecording = notification.object as? Bool ?? false
        DispatchQueue.main.async { [weak self] in
            if let button = self?.statusItem.button {
                let symbolName = isRecording ? "mic.circle.fill" : "mic.fill"
                button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Marsin Dictation")
            }
        }
    }
    
    @objc private func openSettings() {
        if let window = settingsWindow {
            // Reuse existing window
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create a new settings window hosting the SwiftUI SettingsView
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MarsinDictation Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 420, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(self)
    }
}
